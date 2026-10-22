package daemon

import (
	"bytes"
	"encoding/xml"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
)

func InstallService(configPath string, paths Paths) (string, error) {
	executable, err := os.Executable()
	if err != nil {
		return "", err
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	switch runtime.GOOS {
	case "darwin":
		destination := filepath.Join(home, "Library", "LaunchAgents", "com.gitranger.cli.plist")
		contents := fmt.Sprintf(`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.gitranger.cli</string>
<key>ProgramArguments</key><array>
<string>%s</string><string>--config</string><string>%s</string>
<string>daemon</string><string>run</string>
</array>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
<key>StandardOutPath</key><string>%s</string>
<key>StandardErrorPath</key><string>%s</string>
</dict></plist>
`, xmlText(executable), xmlText(configPath), xmlText(paths.Log), xmlText(paths.Log))
		if err := writeServiceFile(destination, contents); err != nil {
			return "", err
		}
		_ = exec.Command("launchctl", "unload", destination).Run()
		if output, err := exec.Command("launchctl", "load", "-w", destination).CombinedOutput(); err != nil {
			return "", fmt.Errorf("launchctl load: %s: %w", output, err)
		}
		return destination, nil
	case "linux":
		destination := filepath.Join(home, ".config", "systemd", "user", "gitranger.service")
		contents := fmt.Sprintf(`[Unit]
Description=GitRanger review daemon
After=network-online.target

[Service]
ExecStart=%s --config %s daemon run
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
`, strconv.Quote(executable), strconv.Quote(configPath))
		if err := writeServiceFile(destination, contents); err != nil {
			return "", err
		}
		if output, err := exec.Command("systemctl", "--user", "daemon-reload").CombinedOutput(); err != nil {
			return "", fmt.Errorf("systemctl daemon-reload: %s: %w", output, err)
		}
		if output, err := exec.Command("systemctl", "--user", "enable", "--now", "gitranger.service").CombinedOutput(); err != nil {
			return "", fmt.Errorf("systemctl enable: %s: %w", output, err)
		}
		return destination, nil
	default:
		return "", fmt.Errorf("service installation is unsupported on %s", runtime.GOOS)
	}
}

func xmlText(value string) string {
	var escaped bytes.Buffer
	_ = xml.EscapeText(&escaped, []byte(value))
	return escaped.String()
}

func writeServiceFile(path, contents string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	temporary := path + ".tmp"
	if err := os.WriteFile(temporary, []byte(contents), 0o600); err != nil {
		return err
	}
	return os.Rename(temporary, path)
}
