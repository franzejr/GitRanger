package daemon

import (
	"path/filepath"

	"github.com/franzejr/gitranger/cli/internal/config"
)

type Paths struct {
	DataDir  string
	Database string
	Socket   string
	Log      string
}

func DefaultPaths() (Paths, error) {
	dir, err := config.DataDir()
	if err != nil {
		return Paths{}, err
	}
	return Paths{
		DataDir:  dir,
		Database: filepath.Join(dir, "state.db"),
		Socket:   filepath.Join(dir, "daemon.sock"),
		Log:      filepath.Join(dir, "daemon.log"),
	}, nil
}
