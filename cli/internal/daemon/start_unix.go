//go:build darwin || linux

package daemon

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"syscall"
	"time"
)

func StartDetached(ctx context.Context, configPath string, paths Paths) error {
	probe, cancel := context.WithTimeout(ctx, 300*time.Millisecond)
	_, err := NewClient(paths.Socket).Snapshot(probe)
	cancel()
	if err == nil {
		return nil
	}
	executable, err := os.Executable()
	if err != nil {
		return err
	}
	logFile, err := os.OpenFile(paths.Log, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	defer logFile.Close()
	command := exec.Command(executable, "--config", configPath, "daemon", "run")
	command.Stdin = nil
	command.Stdout = logFile
	command.Stderr = logFile
	command.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	if err := command.Start(); err != nil {
		return err
	}
	_ = command.Process.Release()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		probe, cancel := context.WithTimeout(ctx, 300*time.Millisecond)
		_, err := NewClient(paths.Socket).Snapshot(probe)
		cancel()
		if err == nil {
			return nil
		}
		time.Sleep(100 * time.Millisecond)
	}
	return fmt.Errorf("daemon did not become ready; inspect %s", paths.Log)
}
