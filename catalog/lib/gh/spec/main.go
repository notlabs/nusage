// Export gh's command tree through Usage's Cobra adapter, without running a command, reading
// a configuration file, loading an extension or touching the network.
//
// This file is not built where it is committed. `catalog/cobra/gh.nu` copies it into a
// checkout of cli/cli at the tag `pin.toml` names, as `cmd/nusage-spec/main.go`, where it may
// import the internal packages the root command's constructor takes, as the upstream
// documentation generator does; a module of its own could not. It is given the tag, and
// prints the spec, or with `--json-fields` the fields each command's `--json` accepts, as
// `cmdutil.AddJSONFlags` records them in the command's annotations.
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"regexp"
	"strings"

	"github.com/cli/cli/v2/internal/config"
	"github.com/cli/cli/v2/internal/gh"
	"github.com/cli/cli/v2/internal/ghrepo"
	"github.com/cli/cli/v2/internal/telemetry"
	"github.com/cli/cli/v2/pkg/cmd/root"
	"github.com/cli/cli/v2/pkg/cmdutil"
	"github.com/cli/cli/v2/pkg/extensions"
	"github.com/cli/cli/v2/pkg/iostreams"
	cobrausage "github.com/jdx/usage/integrations/cobra"
	"github.com/spf13/cobra"
)

func main() {
	args := os.Args[1:]
	fields := len(args) > 0 && args[0] == "--json-fields"
	if fields {
		args = args[1:]
	}
	if len(args) != 1 {
		fail(fmt.Errorf("usage: nusage-spec [--json-fields] <tag>"))
	}
	version := strings.TrimPrefix(args[0], "v")
	clearToolEnvironment()
	// As the upstream docs generator constructs the tree: an empty in-memory configuration,
	// so no alias or host of the user's, no extension, no telemetry, and streams that are
	// not a terminal.
	ios, _, _, _ := iostreams.Test()
	cmd, err := root.NewCmdRoot(&cmdutil.Factory{
		IOStreams: ios,
		Browser:   &browser{},
		Config: func() (gh.Config, error) {
			return config.NewMockConfigFromString(""), nil
		},
		ExtensionManager: &extensionManager{},
	}, &telemetry.NoOpService{}, version, "")
	if err != nil {
		fail(err)
	}
	if fields {
		printJSONFields(cmd)
		return
	}
	// The root's Use line, `gh <command> <subcommand> [flags]`, names placeholders the adapter
	// would read as positionals; the version is the tag's, which gh keeps in an annotation.
	cmd.Use = "gh"
	cmd.Version = version
	normalize(cmd)
	// Usage 7.1.3 leaves reserved words and signed numeric defaults unquoted, and requires
	// defaults to be strings; the adapter escapes newlines in help, so this suffix cannot match
	// inside a quoted description. Remove this shim when the adapter quotes these defaults
	// itself: https://github.com/jdx/usage/issues/1594
	defaults := regexp.MustCompile(`(?m)( default=)(true|false|null|[+-][0-9][^ \t\r\n]*)( \{)?$`)
	spec := defaults.ReplaceAllString(cobrausage.Generate(cmd), `${1}"${2}"${3}`)
	fmt.Print(dedupePersistentFlags(spec))
}

var flagLine = regexp.MustCompile(`^(\s*)flag "([^"]+)"(.*)$`)

// The adapter writes a command's own persistent flag twice: once from its persistent set,
// `global=#true`, and again from its local set, which Cobra fills with the persistent flags
// too; it skips the second only at the root. usage keeps the last, so `pr`'s `-R --repo`
// loses `global` and `pr list` has no `--repo`. Drop the second, with its children: the
// adapter writes a node per line, help with its newlines escaped, and a block closed by `}`
// at the node's own indentation.
func dedupePersistentFlags(spec string) string {
	lines := strings.Split(spec, "\n")
	var kept []string
	global := map[string]map[string]bool{}
	for i := 0; i < len(lines); i++ {
		m := flagLine.FindStringSubmatch(lines[i])
		if m == nil {
			kept = append(kept, lines[i])
			continue
		}
		indent, names, rest := m[1], m[2], m[3]
		if strings.Contains(rest, " global=#true") {
			if global[indent] == nil {
				global[indent] = map[string]bool{}
			}
			global[indent][names] = true
			kept = append(kept, lines[i])
			continue
		}
		if !global[indent][names] {
			kept = append(kept, lines[i])
			continue
		}
		delete(global[indent], names)
		if strings.HasSuffix(rest, " {") {
			for i+1 < len(lines) && lines[i+1] != indent+"}" {
				i++
			}
			i++
		}
	}
	return strings.Join(kept, "\n")
}

// An alternation in a Use line, `[<number> | <url> | <branch>]` or `{<number> | <url>}`: the
// adapter reads a positional from one `<name>` or `[name]` token and nothing from these.
var alternation = regexp.MustCompile(`([\[{])\s*(<[^<>|\[\]{}]+>(?:\.\.\.)?(?:\s*\|\s*<[^<>|\[\]{}]+>(?:\.\.\.)?)+)\s*([\]}])`)

// Each alternation becomes one positional named for its alternatives, optional in `[]` and
// required in `{}`, variadic when any alternative is; the adapter's token forms are
// `[name]`, `<name>` and a `...` suffix. gh's optional positionals are written `[<name>]`,
// which the adapter reads with the angle brackets in the name, so those are taken off too.
// The upstream `scale`-style trailing space in a summary is trimmed as Compose's is.
func normalize(cmd *cobra.Command) {
	cmd.Short = strings.TrimSpace(cmd.Short)
	use := alternation.ReplaceAllStringFunc(cmd.Use, func(group string) string {
		m := alternation.FindStringSubmatch(group)
		var names []string
		variadic := false
		for _, item := range strings.Split(m[2], "|") {
			item = strings.TrimSpace(item)
			if strings.HasSuffix(item, "...") {
				variadic = true
				item = strings.TrimSuffix(item, "...")
			}
			names = append(names, strings.Trim(item, "<>"))
		}
		name := strings.Join(names, "-or-")
		suffix := ""
		if variadic {
			suffix = "..."
		}
		if m[1] == "[" {
			return "[" + name + "]" + suffix
		}
		return "<" + name + ">" + suffix
	})
	use = optional.ReplaceAllString(use, "[$1]$2")
	// A group's Use, `pr <command>`, names the subcommand's place; the adapter passes over
	// `[command]` but would read `<command>` as a required positional.
	if cmd.HasSubCommands() {
		use = placeholder.ReplaceAllString(use, " ")
	}
	cmd.Use = strings.TrimSpace(use)
	for _, sub := range cmd.Commands() {
		normalize(sub)
	}
}

var optional = regexp.MustCompile(`\[<([^<>\[\]]+)>(\.\.\.)?\]`)

var placeholder = regexp.MustCompile(`\s<(?:command|subcommand)>`)

// Every command that takes `--json`, by its words after `gh`, with the fields it accepts.
func printJSONFields(cmd *cobra.Command) {
	fields := map[string][]string{}
	var walk func(c *cobra.Command, path []string)
	walk = func(c *cobra.Command, path []string) {
		if raw, ok := c.Annotations["help:json-fields"]; ok && raw != "" {
			fields[strings.Join(path, " ")] = strings.Split(raw, ",")
		}
		for _, sub := range c.Commands() {
			walk(sub, append(append([]string{}, path...), sub.Name()))
		}
	}
	walk(cmd, nil)
	out, err := json.MarshalIndent(fields, "", "  ")
	if err != nil {
		fail(err)
	}
	fmt.Println(string(out))
}

// gh reads these while the tree is constructed, for hosts, tokens and the help function.
// Clear them only in this exporter process; the invoking shell and the real CLI are unaffected.
func clearToolEnvironment() {
	for _, entry := range os.Environ() {
		name, _, _ := strings.Cut(entry, "=")
		if strings.HasPrefix(name, "GH_") || strings.HasPrefix(name, "GITHUB_") {
			if err := os.Unsetenv(name); err != nil {
				fail(err)
			}
		}
	}
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}

// Implements browser.Browser.
type browser struct{}

func (b *browser) Browse(_ string) error {
	return nil
}

// Implements extensions.ExtensionManager, with no extension installed.
type extensionManager struct{}

func (e *extensionManager) List() []extensions.Extension {
	return nil
}

func (e *extensionManager) Install(_ ghrepo.Interface, _ string) error {
	return nil
}

func (e *extensionManager) InstallLocal(_ string) error {
	return nil
}

func (e *extensionManager) Upgrade(_ string, _ bool) error {
	return nil
}

func (e *extensionManager) Remove(_ string) error {
	return nil
}

func (e *extensionManager) Dispatch(_ []string, _ io.Reader, _, _ io.Writer) (bool, error) {
	return false, nil
}

func (e *extensionManager) Create(_ string, _ extensions.ExtTemplateType) error {
	return nil
}

func (e *extensionManager) EnableDryRunMode() {}

func (e *extensionManager) UpdateDir(_ string) string {
	return ""
}
