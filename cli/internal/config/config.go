package config

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"github.com/google/uuid"
	"gopkg.in/yaml.v3"
)

const CurrentVersion = 1

type Config struct {
	Version      int          `yaml:"version" json:"version"`
	Execution    Execution    `yaml:"execution" json:"execution"`
	Provider     Provider     `yaml:"provider" json:"provider"`
	Repositories []Repository `yaml:"repositories" json:"repositories"`
	Routines     []Routine    `yaml:"routines" json:"routines"`
}

type Execution struct {
	MaxActiveReviews int           `yaml:"max_active_reviews" json:"max_active_reviews"`
	ReviewTimeout    time.Duration `yaml:"-" json:"-"`
	ReviewTimeoutRaw string        `yaml:"review_timeout" json:"review_timeout"`
	PollTick         time.Duration `yaml:"-" json:"-"`
	PollTickRaw      string        `yaml:"poll_tick" json:"poll_tick"`
}

type Provider struct {
	Name      string   `yaml:"name" json:"name"`
	Command   string   `yaml:"command" json:"command"`
	Arguments []string `yaml:"arguments,omitempty" json:"arguments,omitempty"`
	Model     string   `yaml:"model,omitempty" json:"model,omitempty"`
	Effort    string   `yaml:"effort" json:"effort"`
}

type Repository struct {
	ID        string `yaml:"id" json:"id"`
	Name      string `yaml:"name" json:"name"`
	URL       string `yaml:"url" json:"url"`
	LocalPath string `yaml:"local_path,omitempty" json:"local_path,omitempty"`
	Account   string `yaml:"account,omitempty" json:"account,omitempty"`
}

type Routine struct {
	ID                     string        `yaml:"id" json:"id"`
	Name                   string        `yaml:"name" json:"name"`
	Enabled                bool          `yaml:"enabled" json:"enabled"`
	RepositoryIDs          []string      `yaml:"repositories" json:"repositories"`
	Interval               time.Duration `yaml:"-" json:"-"`
	IntervalRaw            string        `yaml:"interval" json:"interval"`
	Scope                  string        `yaml:"scope" json:"scope"`
	SkipDrafts             bool          `yaml:"skip_drafts" json:"skip_drafts"`
	MaxPullRequestsPerPoll int           `yaml:"max_prs_per_poll" json:"max_prs_per_poll"`
	Agents                 []string      `yaml:"agents" json:"agents"`
	Delivery               string        `yaml:"delivery" json:"delivery"`
	MaxAttempts            int           `yaml:"max_attempts" json:"max_attempts"`
}

func Default() Config {
	return Config{
		Version: CurrentVersion,
		Execution: Execution{
			MaxActiveReviews: 2,
			ReviewTimeoutRaw: "3m",
			PollTickRaw:      "15s",
		},
		Provider: Provider{
			Name:    "Claude CLI",
			Command: "claude",
			Arguments: []string{
				"-p", "-", "--output-format", "json", "--no-session-persistence",
			},
			Effort: "low",
		},
	}
}

func DefaultPath() (string, error) {
	dir, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "gitranger", "config.yaml"), nil
}

func DataDir() (string, error) {
	if override := os.Getenv("GITRANGER_DATA_DIR"); override != "" {
		return filepath.Clean(override), nil
	}
	if runtime.GOOS == "windows" {
		dir, err := os.UserConfigDir()
		if err != nil {
			return "", err
		}
		return filepath.Join(dir, "GitRanger"), nil
	}
	dir, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, ".local", "share", "gitranger"), nil
}

func Load(path string) (Config, error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		cfg := Default()
		return cfg, cfg.normalize()
	}
	if err != nil {
		return Config{}, err
	}
	cfg := Default()
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return Config{}, fmt.Errorf("parse config: %w", err)
	}
	if err := cfg.normalize(); err != nil {
		return Config{}, err
	}
	return cfg, nil
}

func Save(path string, cfg Config) error {
	if err := cfg.normalize(); err != nil {
		return err
	}
	data, err := yaml.Marshal(cfg)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	temporary := path + ".tmp"
	if err := os.WriteFile(temporary, data, 0o600); err != nil {
		return err
	}
	return os.Rename(temporary, path)
}

func (c *Config) normalize() error {
	if c.Version == 0 {
		c.Version = CurrentVersion
	}
	if c.Version != CurrentVersion {
		return fmt.Errorf("unsupported config version %d", c.Version)
	}
	if c.Execution.MaxActiveReviews <= 0 {
		c.Execution.MaxActiveReviews = 2
	}
	var err error
	c.Execution.ReviewTimeout, err = duration(c.Execution.ReviewTimeoutRaw, 3*time.Minute)
	if err != nil {
		return fmt.Errorf("review_timeout: %w", err)
	}
	c.Execution.PollTick, err = duration(c.Execution.PollTickRaw, 15*time.Second)
	if err != nil {
		return fmt.Errorf("poll_tick: %w", err)
	}
	if c.Execution.PollTick < time.Second {
		return errors.New("poll_tick must be at least 1s")
	}
	if strings.TrimSpace(c.Provider.Command) == "" {
		return errors.New("provider.command is required")
	}
	if c.Provider.Effort == "" {
		c.Provider.Effort = "low"
	}
	repositories := make(map[string]struct{}, len(c.Repositories))
	for i := range c.Repositories {
		repository := &c.Repositories[i]
		if repository.ID == "" || repository.URL == "" {
			return errors.New("every repository requires id and url")
		}
		if _, exists := repositories[repository.ID]; exists {
			return fmt.Errorf("duplicate repository id %q", repository.ID)
		}
		repositories[repository.ID] = struct{}{}
	}
	for i := range c.Routines {
		routine := &c.Routines[i]
		if routine.ID == "" {
			routine.ID = uuid.NewString()
		}
		if routine.Name == "" {
			return errors.New("every routine requires a name")
		}
		routine.Interval, err = duration(routine.IntervalRaw, 15*time.Minute)
		if err != nil || routine.Interval < time.Minute {
			return fmt.Errorf("routine %q interval must be at least 1m", routine.Name)
		}
		if routine.Scope == "" {
			routine.Scope = "open"
		}
		if routine.Scope != "open" && routine.Scope != "pending_my_review" {
			return fmt.Errorf("routine %q has invalid scope %q", routine.Name, routine.Scope)
		}
		if routine.MaxPullRequestsPerPoll <= 0 {
			routine.MaxPullRequestsPerPoll = 1
		}
		if routine.MaxAttempts <= 0 {
			routine.MaxAttempts = 3
		}
		if routine.Delivery == "" {
			routine.Delivery = "preview"
		}
		if routine.Delivery != "preview" && routine.Delivery != "automatic_comment" {
			return fmt.Errorf("routine %q has invalid delivery %q", routine.Name, routine.Delivery)
		}
		if len(routine.Agents) == 0 {
			routine.Agents = []string{"summary", "security", "performance", "code_quality", "bug_detector"}
		}
		for _, repositoryID := range routine.RepositoryIDs {
			if _, exists := repositories[repositoryID]; !exists {
				return fmt.Errorf("routine %q references unknown repository %q", routine.Name, repositoryID)
			}
		}
	}
	return nil
}

func duration(raw string, fallback time.Duration) (time.Duration, error) {
	if raw == "" {
		return fallback, nil
	}
	return time.ParseDuration(raw)
}

func (c Config) Repository(id string) (Repository, bool) {
	for _, repository := range c.Repositories {
		if repository.ID == id {
			return repository, true
		}
	}
	return Repository{}, false
}
