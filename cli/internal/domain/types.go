package domain

import "time"

type RunStatus string

const (
	RunQueued      RunStatus = "queued"
	RunLoading     RunStatus = "loading"
	RunReviewing   RunStatus = "reviewing"
	RunAggregating RunStatus = "aggregating"
	RunPosting     RunStatus = "posting"
	RunCompleted   RunStatus = "completed"
	RunPosted      RunStatus = "posted"
	RunRetrying    RunStatus = "retrying"
	RunFailed      RunStatus = "failed"
	RunCancelled   RunStatus = "cancelled"
)

func (s RunStatus) Active() bool {
	switch s {
	case RunQueued, RunLoading, RunReviewing, RunAggregating, RunPosting, RunRetrying:
		return true
	default:
		return false
	}
}

type AgentStatus string

const (
	AgentQueued    AgentStatus = "queued"
	AgentReviewing AgentStatus = "reviewing"
	AgentCompleted AgentStatus = "completed"
	AgentFailed    AgentStatus = "failed"
	AgentCancelled AgentStatus = "cancelled"
)

type PullRequest struct {
	Number    int       `json:"number"`
	Title     string    `json:"title"`
	Author    string    `json:"author"`
	URL       string    `json:"url"`
	HeadRef   string    `json:"head_ref"`
	HeadSHA   string    `json:"head_sha"`
	BaseRef   string    `json:"base_ref"`
	Body      string    `json:"body,omitempty"`
	Draft     bool      `json:"draft"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type AgentRun struct {
	ID        string      `json:"id"`
	RunID     string      `json:"run_id"`
	AgentID   string      `json:"agent_id"`
	Name      string      `json:"name"`
	Status    AgentStatus `json:"status"`
	Phase     string      `json:"phase"`
	Provider  string      `json:"provider,omitempty"`
	Model     string      `json:"model,omitempty"`
	Effort    string      `json:"effort,omitempty"`
	Verdict   *bool       `json:"verdict,omitempty"`
	Output    string      `json:"output,omitempty"`
	Error     string      `json:"error,omitempty"`
	StartedAt *time.Time  `json:"started_at,omitempty"`
	EndedAt   *time.Time  `json:"ended_at,omitempty"`
}

type Run struct {
	ID            string     `json:"id"`
	RoutineID     string     `json:"routine_id"`
	RoutineName   string     `json:"routine_name"`
	RepositoryID  string     `json:"repository_id"`
	Repository    string     `json:"repository"`
	PRNumber      int        `json:"pr_number"`
	PRTitle       string     `json:"pr_title"`
	PRAuthor      string     `json:"pr_author"`
	PRURL         string     `json:"pr_url"`
	HeadSHA       string     `json:"head_sha"`
	Status        RunStatus  `json:"status"`
	LastEvent     string     `json:"last_event"`
	Error         string     `json:"error,omitempty"`
	ReviewComment string     `json:"review_comment,omitempty"`
	Attempts      int        `json:"attempts"`
	MaxAttempts   int        `json:"max_attempts"`
	NextAttemptAt *time.Time `json:"next_attempt_at,omitempty"`
	QueuedAt      time.Time  `json:"queued_at"`
	StartedAt     *time.Time `json:"started_at,omitempty"`
	CompletedAt   *time.Time `json:"completed_at,omitempty"`
	Agents        []AgentRun `json:"agents"`
}

type Event struct {
	Sequence  int64     `json:"sequence"`
	RunID     string    `json:"run_id,omitempty"`
	Kind      string    `json:"kind"`
	Message   string    `json:"message"`
	CreatedAt time.Time `json:"created_at"`
}

type Snapshot struct {
	Version    string     `json:"version"`
	StartedAt  time.Time  `json:"started_at"`
	LastPollAt *time.Time `json:"last_poll_at,omitempty"`
	NextPollAt *time.Time `json:"next_poll_at,omitempty"`
	Routines   int        `json:"routines"`
	ActiveRuns int        `json:"active_runs"`
	QueuedRuns int        `json:"queued_runs"`
	FailedRuns int        `json:"failed_runs"`
	RecentRuns []Run      `json:"recent_runs"`
}
