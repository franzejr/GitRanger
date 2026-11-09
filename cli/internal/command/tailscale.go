package command

import (
	"context"
	"fmt"
	"os/exec"
	"strings"
	"time"

	"github.com/spf13/cobra"
)

// Profile selection changes the host's active Tailscale account, including for
// an already-running daemon. It is intentionally opt-in on polling commands.
func withTailscaleProfile(command *cobra.Command) {
	var profile string
	command.Flags().StringVar(&profile, "tailscale-profile", "", "switch the machine's Tailscale account before polling (ID, email, or name)")
	command.PreRunE = func(command *cobra.Command, _ []string) error {
		if !command.Flags().Changed("tailscale-profile") {
			return nil
		}
		return switchTailscaleProfile(command.Context(), profile)
	}
}

func switchTailscaleProfile(ctx context.Context, profile string) error {
	profile = strings.TrimSpace(profile)
	if profile == "" || strings.HasPrefix(profile, "-") {
		return fmt.Errorf("--tailscale-profile requires an account ID, email, or name; list accounts with tailscale switch --list")
	}
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	output, err := exec.CommandContext(ctx, "tailscale", "switch", profile).CombinedOutput()
	if err != nil {
		return fmt.Errorf("switch Tailscale profile %q: %w: %s (list available accounts with tailscale switch --list)", profile, err, strings.TrimSpace(string(output)))
	}
	return nil
}
