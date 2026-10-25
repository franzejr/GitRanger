package process

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"time"
)

type Result struct {
	Stdout   string
	Stderr   string
	ExitCode int
}

func Run(
	ctx context.Context,
	command string,
	arguments []string,
	workingDirectory string,
	input []byte,
	environment []string,
) (Result, error) {
	cmd := exec.Command(command, arguments...)
	configureProcess(cmd)
	if workingDirectory != "" {
		cmd.Dir = workingDirectory
	}
	if environment != nil {
		cmd.Env = environment
	} else {
		cmd.Env = os.Environ()
	}
	if input != nil {
		cmd.Stdin = bytes.NewReader(input)
	}
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Start(); err != nil {
		return Result{}, err
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	select {
	case err := <-done:
		result := resultFor(cmd, stdout.String(), stderr.String())
		if err != nil {
			detail := result.Stderr
			if detail == "" {
				detail = result.Stdout
			}
			return result, fmt.Errorf("%s exited with code %d: %s", command,
				result.ExitCode, concise(detail))
		}
		return result, nil
	case <-ctx.Done():
		terminateProcess(cmd)
		select {
		case <-done:
		case <-time.After(2 * time.Second):
			killProcess(cmd)
			<-done
		}
		return resultFor(cmd, stdout.String(), stderr.String()), ctx.Err()
	}
}

func resultFor(cmd *exec.Cmd, stdout, stderr string) Result {
	exitCode := 0
	if cmd.ProcessState != nil {
		exitCode = cmd.ProcessState.ExitCode()
	}
	return Result{Stdout: stdout, Stderr: stderr, ExitCode: exitCode}
}

func concise(value string) string {
	const limit = 500
	if len(value) <= limit {
		return value
	}
	return value[:limit] + "…"
}
