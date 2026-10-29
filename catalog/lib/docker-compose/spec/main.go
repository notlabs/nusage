// Export Compose's command tree without executing commands or connecting to a daemon.
package main

import (
	"fmt"
	"io"
	"os"
	"regexp"
	"runtime/debug"
	"strings"

	"github.com/docker/cli/cli/command"
	commands "github.com/docker/compose/v5/cmd/compose"
	cobrausage "github.com/jdx/usage/integrations/cobra"
	"github.com/spf13/cobra"
)

func main() {
	clearToolEnvironment()
	cli, err := command.NewDockerCli(
		command.WithInputStream(io.NopCloser(strings.NewReader(""))),
		command.WithOutputStream(io.Discard),
		command.WithErrorStream(io.Discard),
	)
	if err != nil {
		fail(err)
	}
	cmd := commands.RootCommand(cli, &commands.BackendOptions{})
	// The plugin's main adds this command after constructing the tree.
	cmd.AddCommand(commands.HooksCommand())
	// Use the released standalone binary, without depending on a Docker plugin install.
	cmd.Use = "docker-compose"
	cmd.Version = composeVersion()
	trimHelp(cmd)
	// Usage 7.1.3 leaves reserved words and negative numeric defaults unquoted.
	// Usage requires defaults to be strings. Newlines within help are escaped by
	// the adapter, so this suffix cannot match inside a quoted description.
	// Remove this shim when the adapter quotes these defaults itself.
	// Upstream report and reproducer: https://github.com/jdx/usage/issues/1594
	defaults := regexp.MustCompile(`(?m)( default=)(true|false|null|[+-][0-9][^ \t\r\n]*)( \{)?$`)
	spec := defaults.ReplaceAllString(cobrausage.Generate(cmd), `${1}"${2}"${3}`)
	fmt.Print(spec)
}

// The upstream "scale" summary has a trailing space. Keep help identical through
// Usage and Nushell's parsed command descriptions.
func trimHelp(cmd *cobra.Command) {
	cmd.Short = strings.TrimSpace(cmd.Short)
	for _, sub := range cmd.Commands() {
		trimHelp(sub)
	}
}

// These variables affect defaults while the tree is constructed. Clear them only
// in this exporter process; the invoking shell and the real CLI are unaffected.
func clearToolEnvironment() {
	for _, entry := range os.Environ() {
		name, _, _ := strings.Cut(entry, "=")
		if strings.HasPrefix(name, "COMPOSE_") || strings.HasPrefix(name, "DOCKER_") || strings.HasPrefix(name, "BUILDX_") {
			if err := os.Unsetenv(name); err != nil {
				fail(err)
			}
		}
	}
}

func composeVersion() string {
	info, ok := debug.ReadBuildInfo()
	if ok {
		for _, dep := range info.Deps {
			if dep.Path == "github.com/docker/compose/v5" && dep.Replace == nil {
				return strings.TrimPrefix(dep.Version, "v")
			}
		}
	}
	fail(fmt.Errorf("cannot identify the pinned Compose dependency"))
	return ""
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}
