alias "attr usage" = echo

# A value as an argv word: a datetime in ISO 8601, anything else as Nushell writes it.
def "nusage word" []: any -> string {
    if ($in | describe --detailed | get type) == datetime {
        $in | format date "%+"
    } else {
        $in | into string
    }
}

# The argv for a wrapper's parameters: positionals in order, absent ones dropped, each
# preceded by the clause-scoped flags, then the other flags. A flag goes by its value: a
# switch once when on, a count that many times, a list once per item with its value, any
# other value once with its value; null and false add nothing.
def "nusage argv" [positionals: list<any>, flags: record, scoped: record = {}]: nothing -> list<string> {
    let scoped = $scoped | nusage flag-words
    let words = $positionals | compact | each { nusage word }
    let instances = if ($words | is-empty) {
        $scoped
    } else {
        $words | each {|word| $scoped ++ [$word] } | flatten
    }
    $instances ++ ($flags | nusage flag-words)
}

def "nusage flag-words" []: record -> list<string> {
    $in | transpose name value | each {|flag|
        match ($flag.value | describe --detailed | get type) {
            bool => (if $flag.value { [$flag.name] } else { [] })
            int => (0..<$flag.value | each { $flag.name })
            list => ($flag.value | each {|value| [$flag.name ($value | nusage word)] } | flatten)
            nothing => []
            _ => [$flag.name ($flag.value | nusage word)]
        }
    } | flatten
}

# A binary's output decoded as the module's closure decodes it. When that fails and the
# `nusage` this module was generated with is on PATH, the output is held to the schema the
# spec declares, line by line with `--lines`, so the error names what does not match it
# rather than what failed to convert; what failed to convert follows, as the inner error.
# The error is the decoding's own when the output matches or there is no `nusage` to ask,
# and the inner one under why the output could not be held to its schema when the check
# did not run.
def "nusage decoded" [
    text: string
    schema: string
    decode: closure
    --lines
]: nothing -> any {
    try {
        $text | do $decode
    } catch {|err|
        if (which nusage | is-empty) {
            error make $err
        }
        let file = mktemp --tmpdir nusage-XXXXXX.schema.json
        $schema | save --force $file
        let flags = if $lines { [--lines] } else { [] }
        let checked = $text | ^nusage validate $file - ...$flags | complete
        rm $file
        match $checked.exit_code {
            0 => { error make $err }
            1 => {
                $err | error make --unspanned {
                    msg: $"the output does not match its schema\n($checked.stderr | str trim)"
                }
            }
            _ => {
                $err | error make --unspanned {
                    msg: $"the output could not be held to its schema: nusage validate exited ($checked.exit_code)\n($checked.stderr | str trim)"
                }
            }
        }
    }
}

# GitHub CLI
#
# Work seamlessly with GitHub from the command line.
@usage 'version "2.103.3"'
@usage 'example "$ gh issue create\n$ gh repo clone cli/cli\n$ gh pr checkout 321"'
export def main []: nothing -> string {
    ^gh ...(nusage argv [] {})
}

# Manage issues
#
# Work with GitHub issues.
@usage 'long_help "Work with GitHub issues."'
@usage 'flag "-R --repo" help="Select another repository using the `[HOST/]OWNER/REPO` format" global=#true {
        arg <REPO>
    }'
@usage 'example "$ gh issue list\n$ gh issue create --label bug\n$ gh issue view 123 --web"'
export def "gh issue" [
    --repo (-R): string,  # Select another repository using the `[HOST/]OWNER/REPO` format
]: nothing -> string {
    ^gh issue ...(nusage argv [] {--repo: $repo})
}

# Work with issue artifacts (preview)
#
# Working with issue artifacts in the GitHub CLI is in preview and subject to change without notice.
#
# Issue artifacts are Markdown documents, HTML documents and links attached to an issue.
# They are not GitHub Actions artifacts; to download those, use `gh run download`.
@usage 'long_help "Working with issue artifacts in the GitHub CLI is in preview and subject to change without notice.\n\nIssue artifacts are Markdown documents, HTML documents and links attached to an issue.\nThey are not GitHub Actions artifacts; to download those, use `gh run download`.\n"'
export def "gh issue artifact" [
    --repo (-R): string,  # Select another repository using the `[HOST/]OWNER/REPO` format
]: nothing -> string {
    ^gh issue artifact ...(nusage argv [] {--repo: $repo})
}

# Create issue artifacts (preview)
#
# Create one artifact for each file or URL. A text file becomes a document
# named after the file; add `#<name>` to choose a different name. A `.html` or
# `.htm` file becomes an HTML document. A URL, or a `.url` Internet Shortcut
# file, becomes a link; a URL is named after its host.
#
# Artifact names can't contain some characters, such as parentheses. When a
# file's name has them, they're removed: `plan (1).md` is named `plan 1.md`.
#
# Use `--body` to create a single document from text, or `--body-file` to create
# one artifact from a file (`-` reads standard input). `--name` sets its name.
#
# Documents are saved as `generic`, and HTML documents as `embedded_html`. Use
# `--type` to set the type of every document instead, whatever the file
# extension. A plan currently behaves the same as a generic document.
@usage 'alias new'
@usage r#'long_help "Create one artifact for each file or URL. A text file becomes a document\nnamed after the file; add `#<name>` to choose a different name. A `.html` or\n`.htm` file becomes an HTML document. A URL, or a `.url` Internet Shortcut\nfile, becomes a link; a URL is named after its host.\n\nArtifact names can't contain some characters, such as parentheses. When a\nfile's name has them, they're removed: `plan (1).md` is named `plan 1.md`.\n\nUse `--body` to create a single document from text, or `--body-file` to create\none artifact from a file (`-` reads standard input). `--name` sets its name.\n\nDocuments are saved as `generic`, and HTML documents as `embedded_html`. Use\n`--type` to set the type of every document instead, whatever the file\nextension. A plan currently behaves the same as a generic document.\n"'#
@usage r#'flag --attach help="Attach an image or video `file`, in '<file>#<image alt text>' format" {
                arg <ATTACH>
            }'#
@usage 'flag "-b --body" help="Content for a single document" {
                arg <BODY>
            }'
@usage 'flag "-F --body-file" help="Read content for a single artifact from `file` (use \"-\" to read from standard input)" {
                arg <BODY_FILE>
            }'
@usage 'flag --name help="Name for a single artifact" {
                arg <NAME>
            }'
@usage 'flag --type help="Type for documents: {generic|plan|embedded_html}" {
                arg <TYPE>
            }'
@usage 'arg <issue-number-or-issue-url>'
@usage 'arg "[<file>[#<name>]" required=#false'
@usage r#'example "# Create a document from a file\n$ gh issue artifact create 142 signin-plan.md\n\n# Create documents from two files, naming the first\n$ gh issue artifact create 142 'docs/signin-plan.md#Sign-in plan' oauth-research.md\n\n# Create an HTML document from a file\n$ gh issue artifact create 142 menu-prototype.html\n\n# Create a link with a name\n$ gh issue artifact create 142 https://github.com/monalisa/monas-cafe/wiki/OAuth-runbook --name 'Staging OAuth runbook'\n\n# Create a document from standard input\n$ cat order-sync.log | gh issue artifact create 142 --body-file - --name 'Order sync log'\n\n# Upload an image that the document references\n$ gh issue artifact create 142 signin-plan.md --attach ./signin-flow.png"'#
export def "gh issue artifact create" [
    issue_number_or_issue_url: string,
    file_name?: string,
    --repo (-R): string,                # Select another repository using the `[HOST/]OWNER/REPO` format
    --attach: string,                   # Attach an image or video `file`, in '<file>#<image alt text>' format
    --body (-b): string,                # Content for a single document
    --body-file (-F): string,           # Read content for a single artifact from `file` (use "-" to read from standard input)
    --name: string,                     # Name for a single artifact
    --type: string,                     # Type for documents: {generic|plan|embedded_html}
]: nothing -> string {
    ^gh issue artifact create ...(nusage argv [$issue_number_or_issue_url $file_name] {
        --repo: $repo
        --attach: $attach
        --body: $body
        --body-file: $body_file
        --name: $name
        --type: $type
    })
}

# Delete issue artifacts (preview)
#
# Delete artifacts from an issue. A deleted artifact can't be restored.
#
# Name artifacts by their issue and numbers, or by their URLs, which must all be
# on one issue. `<issue>` is an issue number or URL.
#
# In a terminal, deletion requires confirmation. `--yes` skips the prompt and is
# required when prompting is unavailable.
@usage r#'long_help "Delete artifacts from an issue. A deleted artifact can't be restored.\n\nName artifacts by their issue and numbers, or by their URLs, which must all be\non one issue. `<issue>` is an issue number or URL.\n\nIn a terminal, deletion requires confirmation. `--yes` skips the prompt and is\nrequired when prompting is unavailable.\n"'#
@usage 'flag --yes help="Confirm deletion without prompting"'
@usage 'arg <artifact-number>… var=#true'
@usage 'example "# Delete artifact 2 from issue 142\n$ gh issue artifact delete 142 2\n\n# Delete two artifacts without a prompt\n$ gh issue artifact delete 142 2 5 --yes"'
export def "gh issue artifact delete" [
    ...artifact_number: string,
    --repo (-R): string,         # Select another repository using the `[HOST/]OWNER/REPO` format
    --yes,                       # Confirm deletion without prompting
]: nothing -> string {
    ^gh issue artifact delete ...(nusage argv [...$artifact_number] {--repo: $repo, --yes: $yes})
}

# Download issue artifacts (preview)
#
# Download issue artifacts to files. Without artifact numbers, every artifact
# on the issue is downloaded. Artifacts can also be named by their URLs, which
# must all be on one issue. `<issue>` is an issue number or URL.
#
# Each file is named `<number>-<name>`. Markdown documents end in `.md`, HTML
# documents in `.html`, and links are saved as `.url` Internet Shortcut files.
# If a file already exists, that artifact fails unless you use `--clobber` to
# overwrite it or `--skip-existing` to skip it.
#
# Use `--dir` to choose the directory to download files into, `--output` to
# choose the path for a single artifact, or `--output -` to print its content.
# Use `--version` with a single artifact to download an earlier version from
# its edit history.
@usage 'long_help "Download issue artifacts to files. Without artifact numbers, every artifact\non the issue is downloaded. Artifacts can also be named by their URLs, which\nmust all be on one issue. `<issue>` is an issue number or URL.\n\nEach file is named `<number>-<name>`. Markdown documents end in `.md`, HTML\ndocuments in `.html`, and links are saved as `.url` Internet Shortcut files.\nIf a file already exists, that artifact fails unless you use `--clobber` to\noverwrite it or `--skip-existing` to skip it.\n\nUse `--dir` to choose the directory to download files into, `--output` to\nchoose the path for a single artifact, or `--output -` to print its content.\nUse `--version` with a single artifact to download an earlier version from\nits edit history.\n"'
@usage 'flag --clobber help="Overwrite existing files of the same name"'
@usage 'flag "-D --dir" help="The `directory` to download files into" default="." {
                arg <DIR>
            }'
@usage 'flag "-O --output" help="The `file` to write a single artifact to (use \"-\" to write to standard output)" {
                arg <OUTPUT>
            }'
@usage 'flag --skip-existing help="Skip downloading when files of the same name exist"'
@usage 'arg "[artifact-number]…" required=#false var=#true'
@usage r#'example "# Download every artifact on issue 142\n$ gh issue artifact download 142\n\n# Download two artifacts into a folder\n$ gh issue artifact download 142 2 5 --dir notes\n\n# Print one artifact's content\n$ gh issue artifact download 142 2 --output -\n\n# Download an earlier version of one artifact\n$ gh issue artifact download 142 2 --version 5"'#
export def "gh issue artifact download" [
    ...artifact_number: string,
    --repo (-R): string,         # Select another repository using the `[HOST/]OWNER/REPO` format
    --clobber,                   # Overwrite existing files of the same name
    --dir (-D): string,          # The `directory` to download files into
    --output (-O): string,       # The `file` to write a single artifact to (use "-" to write to standard output)
    --skip-existing,             # Skip downloading when files of the same name exist
]: nothing -> string {
    ^gh issue artifact download ...(nusage argv [...$artifact_number] {
        --repo: $repo
        --clobber: $clobber
        --dir: $dir
        --output: $output
        --skip-existing: $skip_existing
    })
}

# Edit an issue artifact (preview)
#
# Rename an issue artifact or replace its content. The type never changes, so a
# link's new content must be an http(s) URL or a `.url` Internet Shortcut file.
#
# Name the artifact by its issue and number, or by its URL. `<issue>` is an
# issue number or URL.
#
# With only `--attach`, the attachments are appended to the current content.
#
# With `--restore-version`, an earlier version's name and content are saved as a
# new version. `gh issue artifact view` shows the edit history.
@usage r#'long_help "Rename an issue artifact or replace its content. The type never changes, so a\nlink's new content must be an http(s) URL or a `.url` Internet Shortcut file.\n\nName the artifact by its issue and number, or by its URL. `<issue>` is an\nissue number or URL.\n\nWith only `--attach`, the attachments are appended to the current content.\n\nWith `--restore-version`, an earlier version's name and content are saved as a\nnew version. `gh issue artifact view` shows the edit history.\n"'#
@usage r#'flag --attach help="Attach an image or video `file`, in '<file>#<image alt text>' format" {
                arg <ATTACH>
            }'#
@usage 'flag "-b --body" help="New content; for a link, a URL" {
                arg <BODY>
            }'
@usage 'flag "-F --body-file" help="Read new content from `file` (use \"-\" to read from standard input)" {
                arg <BODY_FILE>
            }'
@usage 'flag --name help="New name" {
                arg <NAME>
            }'
@usage 'flag --restore-version help="Restore the version with this `number` from the edit history" default="0" {
                arg <RESTORE_VERSION>
            }'
@usage 'arg <artifact-number>'
@usage r#'example "# Rename an artifact\n$ gh issue artifact edit 142 2 --name 'OAuth callback plan v2'\n\n# Replace a document's content with a file\n$ gh issue artifact edit 142 2 --body-file 2-OAuth-callback-plan.md\n\n# Point a link at a new URL\n$ gh issue artifact edit 142 3 --body https://github.com/monalisa/monas-cafe/wiki/OAuth-runbook-v2\n\n# Append an image to a document\n$ gh issue artifact edit 142 2 --attach ./signin-flow.png\n\n# Restore an earlier version\n$ gh issue artifact edit 142 2 --restore-version 5"'#
export def "gh issue artifact edit" [
    artifact_number: string,
    --repo (-R): string,        # Select another repository using the `[HOST/]OWNER/REPO` format
    --attach: string,           # Attach an image or video `file`, in '<file>#<image alt text>' format
    --body (-b): string,        # New content; for a link, a URL
    --body-file (-F): string,   # Read new content from `file` (use "-" to read from standard input)
    --name: string,             # New name
    --restore-version: string,  # Restore the version with this `number` from the edit history
]: nothing -> string {
    ^gh issue artifact edit ...(nusage argv [$artifact_number] {
        --repo: $repo
        --attach: $attach
        --body: $body
        --body-file: $body_file
        --name: $name
        --restore-version: $restore_version
    })
}

# List artifacts on an issue (preview)
#
# List the artifacts on an issue, in number order. Every artifact is listed
# unless you set `--limit`.
@usage 'alias ls'
@usage 'long_help "List the artifacts on an issue, in number order. Every artifact is listed\nunless you set `--limit`.\n"'
@usage 'flag "-q --jq" help="Filter JSON output using a jq `expression`" {
                arg <JQ>
            }'
@usage 'flag --json help="Output JSON with the specified `fields`" {
                arg <JSON>
            }'
@usage 'flag "-L --limit" help="Maximum number of artifacts to fetch" default="0" {
                arg <LIMIT>
            }'
@usage 'flag "-t --template" help="Format JSON output using a Go template; see \"gh help formatting\"" {
                arg <TEMPLATE>
            }'
@usage 'flag --type help="Filter by type: {generic|plan|link|embedded_html}" {
                arg <TYPE>
            }'
@usage 'arg <issue-number-or-issue-url>'
@usage 'example "# List the artifacts on issue 142\n$ gh issue artifact list 142\n\n# List only links\n$ gh issue artifact list 142 --type link\n\n# Print artifact numbers and names as JSON\n$ gh issue artifact list 142 --json number,name"'
export def "gh issue artifact list" [
    issue_number_or_issue_url: string,
    --repo (-R): string,                # Select another repository using the `[HOST/]OWNER/REPO` format
    --jq (-q): string,                  # Filter JSON output using a jq `expression`
    --json: string,                     # Output JSON with the specified `fields`
    --limit (-L): string,               # Maximum number of artifacts to fetch
    --template (-t): string,            # Format JSON output using a Go template; see "gh help formatting"
    --type: string,                     # Filter by type: {generic|plan|link|embedded_html}
]: nothing -> string {
    ^gh issue artifact list ...(nusage argv [$issue_number_or_issue_url] {
        --repo: $repo
        --jq: $jq
        --json: $json
        --limit: $limit
        --template: $template
        --type: $type
    })
}

# View an issue artifact (preview)
#
# Display an issue artifact's name, type, authors, content, and edit history. A
# link shows its URL.
#
# Name the artifact by its issue and number, or by its URL. `<issue>` is an
# issue number or URL.
#
# By default, the current version is shown. Use `--version` to show an earlier
# version from the edit history.
#
# With `--web`, open a document's page on GitHub, or a link's URL.
@usage r#'long_help "Display an issue artifact's name, type, authors, content, and edit history. A\nlink shows its URL.\n\nName the artifact by its issue and number, or by its URL. `<issue>` is an\nissue number or URL.\n\nBy default, the current version is shown. Use `--version` to show an earlier\nversion from the edit history.\n\nWith `--web`, open a document's page on GitHub, or a link's URL.\n"'#
@usage 'flag "-q --jq" help="Filter JSON output using a jq `expression`" {
                arg <JQ>
            }'
@usage 'flag --json help="Output JSON with the specified `fields`" {
                arg <JSON>
            }'
@usage 'flag "-t --template" help="Format JSON output using a Go template; see \"gh help formatting\"" {
                arg <TEMPLATE>
            }'
@usage r#'flag "-w --web" help="Open a document's page on GitHub, or a link's URL"'#
@usage 'arg <artifact-number>'
@usage r#'example "# View artifact 2 on issue 142\n$ gh issue artifact view 142 2\n\n# View an earlier version\n$ gh issue artifact view 142 2 --version 5\n\n# View an artifact by its URL\n$ gh issue artifact view https://github.com/monalisa/monas-cafe/issues/142/artifacts/3\n\n# Open a link artifact in the browser\n$ gh issue artifact view 142 3 --web\n\n# Print an artifact's body\n$ gh issue artifact view 142 2 --json body --jq .body"'#
export def "gh issue artifact view" [
    artifact_number: string,
    --repo (-R): string,      # Select another repository using the `[HOST/]OWNER/REPO` format
    --jq (-q): string,        # Filter JSON output using a jq `expression`
    --json: string,           # Output JSON with the specified `fields`
    --template (-t): string,  # Format JSON output using a Go template; see "gh help formatting"
    --web (-w),               # Open a document's page on GitHub, or a link's URL
]: nothing -> string {
    ^gh issue artifact view ...(nusage argv [$artifact_number] {
        --repo: $repo
        --jq: $jq
        --json: $json
        --template: $template
        --web: $web
    })
}

# Close issue
@usage 'flag "-c --comment" help="Leave a closing comment" {
            arg <COMMENT>
        }'
@usage 'flag --duplicate-of help="Mark as duplicate of another issue by number or URL" {
            arg <DUPLICATE_OF>
        }'
@usage 'flag "-r --reason" help="Reason for closing: {completed|not planned|duplicate}" {
            arg <REASON>
        }'
@usage 'arg <number-or-url>'
@usage 'example "# Close issue\n$ gh issue close 123\n\n# Close issue and add a closing comment\n$ gh issue close 123 --comment \"Closing this issue\"\n\n# Close issue as a duplicate of issue #456\n$ gh issue close 123 --duplicate-of 456\n\n# Close issue as not planned\n$ gh issue close 123 --reason \"not planned\""'
export def "gh issue close" [
    number_or_url: string,
    --repo (-R): string,     # Select another repository using the `[HOST/]OWNER/REPO` format
    --comment (-c): string,  # Leave a closing comment
    --duplicate-of: string,  # Mark as duplicate of another issue by number or URL
    --reason (-r): string,   # Reason for closing: {completed|not planned|duplicate}
]: nothing -> string {
    ^gh issue close ...(nusage argv [$number_or_url] {
        --repo: $repo
        --comment: $comment
        --duplicate-of: $duplicate_of
        --reason: $reason
    })
}

# Add a comment to an issue
#
# Add a comment to a GitHub issue.
#
# Without body text or attachments supplied through flags, the command will
# interactively prompt for the comment text.
#
# Use `--attach` to upload an image or video. If the body already references an
# attached file, such as `![alt](./login.png)`, that reference is rewritten to point
# at the uploaded asset. Paths in a `--body-file` are relative to its directory,
# falling back to the working directory. Any attached file the body does not reference
# is appended to the end of the comment.
# You can attach up to 50 files per command.
#
# Alt text for an image follows the path after `#`, as in
# `--attach './login.png#The login error state'`. Without it the filename is used.
# A reference already in the body keeps the alt text written there. Video renders
# as a player and has no alt text, so it cannot be given any.
@usage r#'long_help "Add a comment to a GitHub issue.\n\nWithout body text or attachments supplied through flags, the command will\ninteractively prompt for the comment text.\n\nUse `--attach` to upload an image or video. If the body already references an\nattached file, such as `![alt](./login.png)`, that reference is rewritten to point\nat the uploaded asset. Paths in a `--body-file` are relative to its directory,\nfalling back to the working directory. Any attached file the body does not reference\nis appended to the end of the comment.\nYou can attach up to 50 files per command.\n\nAlt text for an image follows the path after `#`, as in\n`--attach './login.png#The login error state'`. Without it the filename is used.\nA reference already in the body keeps the alt text written there. Video renders\nas a player and has no alt text, so it cannot be given any.\n"'#
@usage r#'flag --attach help="Attach an image or video `file`, in '<file>#<image alt text>' format" {
            arg <ATTACH>
        }'#
@usage 'flag "-b --body" help="The comment body `text`" {
            arg <BODY>
        }'
@usage 'flag "-F --body-file" help="Read body text from `file` (use \"-\" to read from standard input)" {
            arg <BODY_FILE>
        }'
@usage 'flag --create-if-none help="Create a new comment if no comments are found. Can be used only with --edit-last"'
@usage 'flag --delete-last help="Delete the last comment of the current user"'
@usage 'flag --edit-last help="Edit the last comment of the current user"'
@usage 'flag "-e --editor" help="Skip prompts and open the text editor to write the body in"'
@usage 'flag "-w --web" help="Open the web browser to write the comment"'
@usage 'flag --yes help="Skip the delete confirmation prompt when --delete-last is provided"'
@usage 'arg <number-or-url>'
@usage r#'example "# Add a comment to an issue\n$ gh issue comment 12 --body \"Hi from GitHub CLI\"\n\n# Attach a screenshot, with alt text after \"#\"\n$ gh issue comment 12 --attach './login.png#The login error state'\n\n# Attach multiple files by repeating the flag\n$ gh issue comment 12 --attach ./before.png --attach ./after.png"'#
export def "gh issue comment" [
    number_or_url: string,
    --repo (-R): string,       # Select another repository using the `[HOST/]OWNER/REPO` format
    --attach: string,          # Attach an image or video `file`, in '<file>#<image alt text>' format
    --body (-b): string,       # The comment body `text`
    --body-file (-F): string,  # Read body text from `file` (use "-" to read from standard input)
    --create-if-none,          # Create a new comment if no comments are found. Can be used only with --edit-last
    --delete-last,             # Delete the last comment of the current user
    --edit-last,               # Edit the last comment of the current user
    --editor (-e),             # Skip prompts and open the text editor to write the body in
    --web (-w),                # Open the web browser to write the comment
    --yes,                     # Skip the delete confirmation prompt when --delete-last is provided
]: nothing -> string {
    ^gh issue comment ...(nusage argv [$number_or_url] {
        --repo: $repo
        --attach: $attach
        --body: $body
        --body-file: $body_file
        --create-if-none: $create_if_none
        --delete-last: $delete_last
        --edit-last: $edit_last
        --editor: $editor
        --web: $web
        --yes: $yes
    })
}

# Create a new issue
#
# Create an issue on GitHub.
#
# Use `--attach` to upload an image or video. The attachment is appended to the
# body. If the body references an attached file, such as `![alt](./login.png)`, that
# reference is rewritten to point at the uploaded asset instead. Paths in a
# `--body-file` are relative to its directory, falling back to the working directory.
# You can attach up to 50 files per command.
#
# Alt text for an image follows the path after `#`, as in
# `--attach './login.png#The login error state'`. Without it the filename is used.
# A reference already in the body keeps the alt text written there. Video renders
# as a player and has no alt text, so it cannot be given any.
#
# If some attachments upload and others fail, the issue is still created with the
# ones that succeeded. The command then exits with a non-zero status, but the new
# issue's URL is still printed to stdout.
#
# Adding an issue to projects requires authorization with the `project` scope.
# To authorize, run `gh auth refresh -s project`.
#
# The `--assignee` flag supports the following special values:
# - `@me`: assign yourself
# - `@copilot`: assign Copilot (not supported on GitHub Enterprise Server)
@usage 'alias new'
@usage r#'long_help "Create an issue on GitHub.\n\nUse `--attach` to upload an image or video. The attachment is appended to the\nbody. If the body references an attached file, such as `![alt](./login.png)`, that\nreference is rewritten to point at the uploaded asset instead. Paths in a\n`--body-file` are relative to its directory, falling back to the working directory.\nYou can attach up to 50 files per command.\n\nAlt text for an image follows the path after `#`, as in\n`--attach './login.png#The login error state'`. Without it the filename is used.\nA reference already in the body keeps the alt text written there. Video renders\nas a player and has no alt text, so it cannot be given any.\n\nIf some attachments upload and others fail, the issue is still created with the\nones that succeeded. The command then exits with a non-zero status, but the new\nissue's URL is still printed to stdout.\n\nAdding an issue to projects requires authorization with the `project` scope.\nTo authorize, run `gh auth refresh -s project`.\n\nThe `--assignee` flag supports the following special values:\n- `@me`: assign yourself\n- `@copilot`: assign Copilot (not supported on GitHub Enterprise Server)\n"'#
@usage 'flag "-a --assignee" help="Assign people by their `login`. Use \"@me\" to self-assign." {
            arg <ASSIGNEE>
        }'
@usage r#'flag --attach help="Attach an image or video `file`, in '<file>#<image alt text>' format" {
            arg <ATTACH>
        }'#
@usage 'flag --blocked-by help="Mark the new issue as blocked by these issue `numbers` or URLs" {
            arg <BLOCKED_BY>
        }'
@usage 'flag --blocking help="Mark the new issue as blocking these issue `numbers` or URLs" {
            arg <BLOCKING>
        }'
@usage 'flag "-b --body" help="Supply a body. Will prompt for one otherwise." {
            arg <BODY>
        }'
@usage 'flag "-F --body-file" help="Read body text from `file` (use \"-\" to read from standard input)" {
            arg <BODY_FILE>
        }'
@usage 'flag "-e --editor" help="Skip prompts and open the text editor to write the title and body in. The first line is the title and the remaining text is the body."'
@usage 'flag "-l --label" help="Add labels by `name`" {
            arg <LABEL>
        }'
@usage 'flag "-m --milestone" help="Add the issue to a milestone by `name`" {
            arg <MILESTONE>
        }'
@usage 'flag --parent help="Add the new issue as a sub-issue of the specified parent `number` or URL" {
            arg <PARENT>
        }'
@usage 'flag "-p --project" help="Add the issue to projects by `title`" {
            arg <PROJECT>
        }'
@usage 'flag --recover help="Recover input from a failed run of create" {
            arg <RECOVER>
        }'
@usage 'flag "-T --template" help="Template `name` to use as starting body text" {
            arg <TEMPLATE>
        }'
@usage 'flag "-t --title" help="Supply a title. Will prompt for one otherwise." {
            arg <TITLE>
        }'
@usage 'flag --type help="Set the issue type by `name`" {
            arg <TYPE>
        }'
@usage 'flag "-w --web" help="Open the browser to create an issue"'
@usage r#'example "$ gh issue create --title \"I found a bug\" --body \"Nothing works\"\n$ gh issue create --attach './login.png#The login error state'\n$ gh issue create --attach ./before.png --attach ./after.png\n$ gh issue create --label \"bug,help wanted\"\n$ gh issue create --label bug --label \"help wanted\"\n$ gh issue create --assignee monalisa,hubot\n$ gh issue create --assignee \"@me\"\n$ gh issue create --assignee \"@copilot\"\n$ gh issue create --project \"Roadmap\"\n$ gh issue create --template \"Bug Report\"\n$ gh issue create --type Bug\n$ gh issue create --parent 100\n$ gh issue create --parent https://github.com/cli/go-gh/issues/42\n$ gh issue create --blocked-by 200,201 --blocking 300"'#
export def "gh issue create" [
    --repo (-R): string,       # Select another repository using the `[HOST/]OWNER/REPO` format
    --assignee (-a): string,   # Assign people by their `login`. Use "@me" to self-assign.
    --attach: string,          # Attach an image or video `file`, in '<file>#<image alt text>' format
    --blocked-by: string,      # Mark the new issue as blocked by these issue `numbers` or URLs
    --blocking: string,        # Mark the new issue as blocking these issue `numbers` or URLs
    --body (-b): string,       # Supply a body. Will prompt for one otherwise.
    --body-file (-F): string,  # Read body text from `file` (use "-" to read from standard input)
    --editor (-e),             # Skip prompts and open the text editor to write the title and body in. The first line is the title and the remaining text is the body.
    --label (-l): string,      # Add labels by `name`
    --milestone (-m): string,  # Add the issue to a milestone by `name`
    --parent: string,          # Add the new issue as a sub-issue of the specified parent `number` or URL
    --project (-p): string,    # Add the issue to projects by `title`
    --recover: string,         # Recover input from a failed run of create
    --template (-T): string,   # Template `name` to use as starting body text
    --title (-t): string,      # Supply a title. Will prompt for one otherwise.
    --type: string,            # Set the issue type by `name`
    --web (-w),                # Open the browser to create an issue
]: nothing -> string {
    ^gh issue create ...(nusage argv [] {
        --repo: $repo
        --assignee: $assignee
        --attach: $attach
        --blocked-by: $blocked_by
        --blocking: $blocking
        --body: $body
        --body-file: $body_file
        --editor: $editor
        --label: $label
        --milestone: $milestone
        --parent: $parent
        --project: $project
        --recover: $recover
        --template: $template
        --title: $title
        --type: $type
        --web: $web
    })
}

# Delete issue
@usage 'flag --confirm help="Confirm deletion without prompting" hide=#true deprecated="use `--yes` instead"'
@usage 'flag --yes help="Confirm deletion without prompting"'
@usage 'arg <number-or-url>'
export def "gh issue delete" [
    number_or_url: string,
    --repo (-R): string,    # Select another repository using the `[HOST/]OWNER/REPO` format
    --yes,                  # Confirm deletion without prompting
]: nothing -> string {
    ^gh issue delete ...(nusage argv [$number_or_url] {--repo: $repo, --yes: $yes})
}

# Manage linked branches for an issue
#
# When using the `--base` flag, the new development branch will be created from the specified
# remote branch. The new branch will be configured as the base branch for pull requests created using
# `gh pr create`.
@usage 'long_help "Manage linked branches for an issue.\n\nWhen using the `--base` flag, the new development branch will be created from the specified\nremote branch. The new branch will be configured as the base branch for pull requests created using\n`gh pr create`.\n"'
@usage 'flag "-b --base" help="Name of the remote branch you want to make your new branch from" {
            arg <BASE>
        }'
@usage 'flag --branch-repo help="Name or URL of the repository where you want to create your new branch" {
            arg <BRANCH_REPO>
        }'
@usage 'flag "-c --checkout" help="Checkout the branch after creating it"'
@usage r#'flag "-i --issue-repo" help="Name or URL of the issue's repository" hide=#true deprecated="use `--repo` instead" {
            arg <ISSUE_REPO>
        }'#
@usage 'flag "-l --list" help="List linked branches for the issue"'
@usage 'flag "-n --name" help="Name of the branch to create" {
            arg <NAME>
        }'
@usage 'flag --worktree help="Check out the branch into a worktree at the given `path`" {
            arg <WORKTREE>
        }'
@usage 'arg <number-or-url>'
@usage 'example "# List branches for issue 123\n$ gh issue develop --list 123\n\n# List branches for issue 123 in repo cli/cli\n$ gh issue develop --list --repo cli/cli 123\n\n# Create a branch for issue 123 based on the my-feature branch\n$ gh issue develop 123 --base my-feature\n\n# Create a branch for issue 123 and check it out\n$ gh issue develop 123 --checkout\n\n# Create a branch for issue 123 and check it out in a worktree\n$ gh issue develop 123 --checkout --worktree /path/to/wt-feature\n\n# Create a branch in repo monalisa/cli for issue 123 in repo cli/cli\n$ gh issue develop 123 --repo cli/cli --branch-repo monalisa/cli"'
export def "gh issue develop" [
    number_or_url: string,
    --repo (-R): string,    # Select another repository using the `[HOST/]OWNER/REPO` format
    --base (-b): string,    # Name of the remote branch you want to make your new branch from
    --branch-repo: string,  # Name or URL of the repository where you want to create your new branch
    --checkout (-c),        # Checkout the branch after creating it
    --list (-l),            # List linked branches for the issue
    --name (-n): string,    # Name of the branch to create
    --worktree: string,     # Check out the branch into a worktree at the given `path`
]: nothing -> string {
    ^gh issue develop ...(nusage argv [$number_or_url] {
        --repo: $repo
        --base: $base
        --branch-repo: $branch_repo
        --checkout: $checkout
        --list: $list
        --name: $name
        --worktree: $worktree
    })
}

# Edit issues
#
# Edit one or more issues within the same repository.
#
# Editing issues' projects requires authorization with the `project` scope.
# To authorize, run `gh auth refresh -s project`.
#
# Use `--attach` to upload an image or video to a single issue. Without a body
# flag the issue keeps the body it already has and the attachment is appended to it.
# If the body references an attached file, such as `![alt](./login.png)`, that
# reference is rewritten to point at the uploaded asset instead. Paths in a
# `--body-file` are relative to its directory, falling back to the working directory.
# You can attach up to 50 files per command.
#
# Alt text for an image follows the path after `#`, as in
# `--attach './login.png#The login error state'`. Without it the filename is used.
# A reference already in the body keeps the alt text written there. Video renders
# as a player and has no alt text, so it cannot be given any.
#
# If some attachments upload and others fail, the issue is still updated with the
# ones that succeeded. The command then exits with a non-zero status, but the edited
# issue URLs are still printed to stdout.
#
# The `--add-assignee` and `--remove-assignee` flags both support
# the following special values:
# - `@me`: assign or unassign yourself
# - `@copilot`: assign or unassign Copilot (not supported on GitHub Enterprise Server)
@usage r#'long_help "Edit one or more issues within the same repository.\n\nEditing issues' projects requires authorization with the `project` scope.\nTo authorize, run `gh auth refresh -s project`.\n\nUse `--attach` to upload an image or video to a single issue. Without a body\nflag the issue keeps the body it already has and the attachment is appended to it.\nIf the body references an attached file, such as `![alt](./login.png)`, that\nreference is rewritten to point at the uploaded asset instead. Paths in a\n`--body-file` are relative to its directory, falling back to the working directory.\nYou can attach up to 50 files per command.\n\nAlt text for an image follows the path after `#`, as in\n`--attach './login.png#The login error state'`. Without it the filename is used.\nA reference already in the body keeps the alt text written there. Video renders\nas a player and has no alt text, so it cannot be given any.\n\nIf some attachments upload and others fail, the issue is still updated with the\nones that succeeded. The command then exits with a non-zero status, but the edited\nissue URLs are still printed to stdout.\n\nThe `--add-assignee` and `--remove-assignee` flags both support\nthe following special values:\n- `@me`: assign or unassign yourself\n- `@copilot`: assign or unassign Copilot (not supported on GitHub Enterprise Server)\n"'#
@usage 'flag --add-assignee help="Add assigned users by their `login`. Use \"@me\" to assign yourself, or \"@copilot\" to assign Copilot." {
            arg <ADD_ASSIGNEE>
        }'
@usage r#'flag --add-blocked-by help="Add 'blocked by' relationships by issue `number` or URL" {
            arg <ADD_BLOCKED_BY>
        }'#
@usage r#'flag --add-blocking help="Add 'blocking' relationships by issue `number` or URL" {
            arg <ADD_BLOCKING>
        }'#
@usage 'flag --add-label help="Add labels by `name`" {
            arg <ADD_LABEL>
        }'
@usage 'flag --add-project help="Add the issue to projects by `title`" {
            arg <ADD_PROJECT>
        }'
@usage 'flag --add-sub-issue help="Add sub-issues by `number` or URL" {
            arg <ADD_SUB_ISSUE>
        }'
@usage r#'flag --attach help="Attach an image or video `file`, in '<file>#<image alt text>' format" {
            arg <ATTACH>
        }'#
@usage 'flag "-b --body" help="Set the new body." {
            arg <BODY>
        }'
@usage 'flag "-F --body-file" help="Read body text from `file` (use \"-\" to read from standard input)" {
            arg <BODY_FILE>
        }'
@usage 'flag "-m --milestone" help="Edit the milestone the issue belongs to by `name`" {
            arg <MILESTONE>
        }'
@usage 'flag --parent help="Set the parent issue by `number` or URL" {
            arg <PARENT>
        }'
@usage 'flag --remove-assignee help="Remove assigned users by their `login`. Use \"@me\" to unassign yourself, or \"@copilot\" to unassign Copilot." {
            arg <REMOVE_ASSIGNEE>
        }'
@usage r#'flag --remove-blocked-by help="Remove 'blocked by' relationships by issue `number` or URL" {
            arg <REMOVE_BLOCKED_BY>
        }'#
@usage r#'flag --remove-blocking help="Remove 'blocking' relationships by issue `number` or URL" {
            arg <REMOVE_BLOCKING>
        }'#
@usage 'flag --remove-label help="Remove labels by `name`" {
            arg <REMOVE_LABEL>
        }'
@usage 'flag --remove-milestone help="Remove the milestone association from the issue"'
@usage 'flag --remove-parent help="Remove the parent issue"'
@usage 'flag --remove-project help="Remove the issue from projects by `title`" {
            arg <REMOVE_PROJECT>
        }'
@usage 'flag --remove-sub-issue help="Remove sub-issues by `number` or URL" {
            arg <REMOVE_SUB_ISSUE>
        }'
@usage 'flag --remove-type help="Remove the issue type from the issue"'
@usage 'flag "-t --title" help="Set the new title." {
            arg <TITLE>
        }'
@usage 'flag --type help="Set the issue type by `name`" {
            arg <TYPE>
        }'
@usage 'arg <numbers-or-urls>'
@usage r#'example "$ gh issue edit 23 --title \"I found a bug\" --body \"Nothing works\"\n$ gh issue edit 23 --add-label \"bug,help wanted\" --remove-label \"core\"\n$ gh issue edit 23 --add-assignee \"@me\" --remove-assignee monalisa,hubot\n$ gh issue edit 23 --add-assignee \"@copilot\"\n$ gh issue edit 23 --add-project \"Roadmap\" --remove-project v1,v2\n$ gh issue edit 23 --milestone \"Version 1\"\n$ gh issue edit 23 --remove-milestone\n$ gh issue edit 23 --body-file body.txt\n$ gh issue edit 23 --attach './login.png#The login error state'\n$ gh issue edit 23 --attach ./before.png --attach ./after.png\n$ gh issue edit 23 34 --add-label \"help wanted\"\n$ gh issue edit 23 --type Bug\n$ gh issue edit 23 --remove-type\n$ gh issue edit 23 --parent 100\n$ gh issue edit 23 --remove-parent\n$ gh issue edit 100 --add-sub-issue 123,124\n$ gh issue edit 123 --add-blocked-by 200 --add-blocking 300,301"'#
export def "gh issue edit" [
    numbers_or_urls: string,
    --repo (-R): string,          # Select another repository using the `[HOST/]OWNER/REPO` format
    --add-assignee: string,       # Add assigned users by their `login`. Use "@me" to assign yourself, or "@copilot" to assign Copilot.
    --add-blocked-by: string,     # Add 'blocked by' relationships by issue `number` or URL
    --add-blocking: string,       # Add 'blocking' relationships by issue `number` or URL
    --add-label: string,          # Add labels by `name`
    --add-project: string,        # Add the issue to projects by `title`
    --add-sub-issue: string,      # Add sub-issues by `number` or URL
    --attach: string,             # Attach an image or video `file`, in '<file>#<image alt text>' format
    --body (-b): string,          # Set the new body.
    --body-file (-F): string,     # Read body text from `file` (use "-" to read from standard input)
    --milestone (-m): string,     # Edit the milestone the issue belongs to by `name`
    --parent: string,             # Set the parent issue by `number` or URL
    --remove-assignee: string,    # Remove assigned users by their `login`. Use "@me" to unassign yourself, or "@copilot" to unassign Copilot.
    --remove-blocked-by: string,  # Remove 'blocked by' relationships by issue `number` or URL
    --remove-blocking: string,    # Remove 'blocking' relationships by issue `number` or URL
    --remove-label: string,       # Remove labels by `name`
    --remove-milestone,           # Remove the milestone association from the issue
    --remove-parent,              # Remove the parent issue
    --remove-project: string,     # Remove the issue from projects by `title`
    --remove-sub-issue: string,   # Remove sub-issues by `number` or URL
    --remove-type,                # Remove the issue type from the issue
    --title (-t): string,         # Set the new title.
    --type: string,               # Set the issue type by `name`
]: nothing -> string {
    ^gh issue edit ...(nusage argv [$numbers_or_urls] {
        --repo: $repo
        --add-assignee: $add_assignee
        --add-blocked-by: $add_blocked_by
        --add-blocking: $add_blocking
        --add-label: $add_label
        --add-project: $add_project
        --add-sub-issue: $add_sub_issue
        --attach: $attach
        --body: $body
        --body-file: $body_file
        --milestone: $milestone
        --parent: $parent
        --remove-assignee: $remove_assignee
        --remove-blocked-by: $remove_blocked_by
        --remove-blocking: $remove_blocking
        --remove-label: $remove_label
        --remove-milestone: $remove_milestone
        --remove-parent: $remove_parent
        --remove-project: $remove_project
        --remove-sub-issue: $remove_sub_issue
        --remove-type: $remove_type
        --title: $title
        --type: $type
    })
}

# List issues in a repository
#
# List issues in a GitHub repository. By default, this only lists open issues.
#
# The search query syntax is documented here:
# <https://docs.github.com/en/search-github/searching-on-github/searching-issues-and-pull-requests>
#
# On supported GitHub hosts, advanced issue search syntax can be used in the
# `--search` query. For more information about advanced issue search, see:
# <https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/filtering-and-searching-issues-and-pull-requests#building-advanced-filters-for-issues>
@usage 'alias ls'
@usage 'long_help "List issues in a GitHub repository. By default, this only lists open issues.\n\nThe search query syntax is documented here:\n<https://docs.github.com/en/search-github/searching-on-github/searching-issues-and-pull-requests>\n\nOn supported GitHub hosts, advanced issue search syntax can be used in the\n`--search` query. For more information about advanced issue search, see:\n<https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/filtering-and-searching-issues-and-pull-requests#building-advanced-filters-for-issues>\n"'
@usage 'flag --app help="Filter by GitHub App author" {
            arg <APP>
        }'
@usage 'flag "-a --assignee" help="Filter by assignee" {
            arg <ASSIGNEE>
        }'
@usage 'flag "-A --author" help="Filter by author (use --app to filter by a GitHub App)" {
            arg <AUTHOR>
        }'
@usage 'flag "-q --jq" help="Filter JSON output using a jq `expression`" hide=#true {
            arg <JQ>
        }'
@usage 'flag --json help="Output JSON with the specified `fields`" {
            arg <JSON>
        }'
@usage 'flag "-l --label" help="Filter by label" {
            arg <LABEL>
        }'
@usage 'flag "-L --limit" help="Maximum number of issues to fetch" default="30" {
            arg <LIMIT>
        }'
@usage 'flag --mention help="Filter by mention" {
            arg <MENTION>
        }'
@usage 'flag "-m --milestone" help="Filter by milestone number or title" {
            arg <MILESTONE>
        }'
@usage 'flag "-S --search" help="Search issues with `query`" {
            arg <SEARCH>
        }'
@usage 'flag "-s --state" help="Filter by state: {open|closed|all}" default=open {
            arg <STATE>
        }'
@usage 'flag "-t --template" help="Format JSON output using a Go template; see \"gh help formatting\"" hide=#true {
            arg <TEMPLATE>
        }'
@usage 'flag --type help="Filter by issue type `name`" {
            arg <TYPE>
        }'
@usage 'flag "-w --web" help="List issues in the web browser" hide=#true'
@usage 'example "$ gh issue list --label \"bug\" --label \"help wanted\"\n$ gh issue list --author monalisa\n$ gh issue list --app dependabot\n$ gh issue list --assignee \"@me\"\n$ gh issue list --milestone \"The big 1.0\"\n$ gh issue list --search \"error no:assignee sort:created-asc\"\n$ gh issue list --state all\n$ gh issue list --type Bug"'
@usage 'output "json" framing="json" { schema "{\n  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",\n  \"title\": \"The issues `gh issue list --json` selects, one array\",\n  \"type\": \"array\",\n  \"items\": {\"$ref\": \"#/$defs/issue\"},\n  \"$defs\": {\n    \"author\": {\n      \"type\": \"object\",\n      \"required\": [\"is_bot\", \"login\"],\n      \"additionalProperties\": false,\n      \"properties\": {\n        \"is_bot\": {\"type\": \"boolean\"},\n        \"login\": {\"type\": \"string\"},\n        \"id\": {\"type\": \"string\"},\n        \"name\": {\"type\": \"string\"}\n      }\n    },\n    \"label\": {\n      \"type\": \"object\",\n      \"required\": [\"id\", \"name\", \"description\", \"color\"],\n      \"additionalProperties\": false,\n      \"properties\": {\n        \"id\": {\"type\": \"string\"},\n        \"name\": {\"type\": \"string\"},\n        \"description\": {\"type\": \"string\"},\n        \"color\": {\"type\": \"string\"}\n      }\n    },\n    \"user\": {\n      \"type\": \"object\",\n      \"required\": [\"id\", \"login\", \"name\", \"databaseId\"],\n      \"additionalProperties\": false,\n      \"properties\": {\n        \"id\": {\"type\": \"string\"},\n        \"login\": {\"type\": \"string\"},\n        \"name\": {\"type\": \"string\"},\n        \"databaseId\": {\"type\": \"integer\"}\n      }\n    },\n    \"issue\": {\n      \"type\": \"object\",\n      \"required\": [\n        \"number\",\n        \"title\",\n        \"state\",\n        \"stateReason\",\n        \"url\",\n        \"author\",\n        \"createdAt\",\n        \"updatedAt\",\n        \"closedAt\",\n        \"labels\",\n        \"assignees\",\n        \"body\"\n      ],\n      \"additionalProperties\": false,\n      \"properties\": {\n        \"number\": {\"type\": \"integer\"},\n        \"title\": {\"type\": \"string\"},\n        \"state\": {\"enum\": [\"OPEN\", \"CLOSED\"]},\n        \"stateReason\": {\"type\": \"string\"},\n        \"url\": {\"type\": \"string\"},\n        \"author\": {\"$ref\": \"#/$defs/author\"},\n        \"createdAt\": {\"type\": \"string\", \"format\": \"date-time\"},\n        \"updatedAt\": {\"type\": \"string\", \"format\": \"date-time\"},\n        \"closedAt\": {\"anyOf\": [{\"type\": \"string\", \"format\": \"date-time\"}, {\"type\": \"null\"}]},\n        \"labels\": {\"type\": \"array\", \"items\": {\"$ref\": \"#/$defs/label\"}},\n        \"assignees\": {\"type\": \"array\", \"items\": {\"$ref\": \"#/$defs/user\"}},\n        \"body\": {\"type\": \"string\"}\n      }\n    }\n  }\n}\n" }'
export def "gh issue list" [
    --repo (-R): string,       # Select another repository using the `[HOST/]OWNER/REPO` format
    --app: string,             # Filter by GitHub App author
    --assignee (-a): string,   # Filter by assignee
    --author (-A): string,     # Filter by author (use --app to filter by a GitHub App)
    --label (-l): string,      # Filter by label
    --limit (-L): string,      # Maximum number of issues to fetch
    --mention: string,         # Filter by mention
    --milestone (-m): string,  # Filter by milestone number or title
    --search (-S): string,     # Search issues with `query`
    --state (-s): string,      # Filter by state: {open|closed|all}
    --type: string,            # Filter by issue type `name`
]: nothing -> table<number: int, title: string, state: string, stateReason: string, url: string, author: record<is_bot: bool, login: string, id: oneof<string, nothing>, name: oneof<string, nothing>>, createdAt: datetime, updatedAt: datetime, closedAt: oneof<datetime, nothing>, labels: table<id: string, name: string, description: string, color: string>, assignees: table<id: string, login: string, name: string, databaseId: int>, body: string> {
    let text = ^gh issue list --json "number,title,state,stateReason,url,author,createdAt,updatedAt,closedAt,labels,assignees,body" ...(nusage argv [] {
        --repo: $repo
        --app: $app
        --assignee: $assignee
        --author: $author
        --label: $label
        --limit: $limit
        --mention: $mention
        --milestone: $milestone
        --search: $search
        --state: $state
        --type: $type
    })
    nusage decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"title\":\"The issues `gh issue list --json` selects, one array\",\"type\":\"array\",\"items\":{\"$ref\":\"#/$defs/issue\"},\"$defs\":{\"author\":{\"type\":\"object\",\"required\":[\"is_bot\",\"login\"],\"additionalProperties\":false,\"properties\":{\"is_bot\":{\"type\":\"boolean\"},\"login\":{\"type\":\"string\"},\"id\":{\"type\":\"string\"},\"name\":{\"type\":\"string\"}}},\"label\":{\"type\":\"object\",\"required\":[\"id\",\"name\",\"description\",\"color\"],\"additionalProperties\":false,\"properties\":{\"id\":{\"type\":\"string\"},\"name\":{\"type\":\"string\"},\"description\":{\"type\":\"string\"},\"color\":{\"type\":\"string\"}}},\"user\":{\"type\":\"object\",\"required\":[\"id\",\"login\",\"name\",\"databaseId\"],\"additionalProperties\":false,\"properties\":{\"id\":{\"type\":\"string\"},\"login\":{\"type\":\"string\"},\"name\":{\"type\":\"string\"},\"databaseId\":{\"type\":\"integer\"}}},\"issue\":{\"type\":\"object\",\"required\":[\"number\",\"title\",\"state\",\"stateReason\",\"url\",\"author\",\"createdAt\",\"updatedAt\",\"closedAt\",\"labels\",\"assignees\",\"body\"],\"additionalProperties\":false,\"properties\":{\"number\":{\"type\":\"integer\"},\"title\":{\"type\":\"string\"},\"state\":{\"enum\":[\"OPEN\",\"CLOSED\"]},\"stateReason\":{\"type\":\"string\"},\"url\":{\"type\":\"string\"},\"author\":{\"$ref\":\"#/$defs/author\"},\"createdAt\":{\"type\":\"string\",\"format\":\"date-time\"},\"updatedAt\":{\"type\":\"string\",\"format\":\"date-time\"},\"closedAt\":{\"anyOf\":[{\"type\":\"string\",\"format\":\"date-time\"},{\"type\":\"null\"}]},\"labels\":{\"type\":\"array\",\"items\":{\"$ref\":\"#/$defs/label\"}},\"assignees\":{\"type\":\"array\",\"items\":{\"$ref\":\"#/$defs/user\"}},\"body\":{\"type\":\"string\"}}}}}" { from json | update author { default null id } | update author { default null name } | into datetime createdAt | into datetime updatedAt | update closedAt {|row| if $row.closedAt == null { null } else { $row.closedAt | into datetime } } }
}

# Lock issue conversation
@usage 'flag "-r --reason" help="Optional reason for locking conversation (off_topic, resolved, spam, too_heated)." {
            arg <REASON>
        }'
@usage 'arg <number-or-url>'
export def "gh issue lock" [
    number_or_url: string,
    --repo (-R): string,    # Select another repository using the `[HOST/]OWNER/REPO` format
    --reason (-r): string,  # Optional reason for locking conversation (off_topic, resolved, spam, too_heated).
]: nothing -> string {
    ^gh issue lock ...(nusage argv [$number_or_url] {--repo: $repo, --reason: $reason})
}

# Pin an issue
#
# Pin an issue to a repository.
#
# The issue can be specified by issue number or URL.
@usage 'long_help "Pin an issue to a repository.\n\nThe issue can be specified by issue number or URL.\n"'
@usage 'arg <number-or-url>'
@usage 'example "# Pin an issue to the current repository\n$ gh issue pin 23\n\n# Pin an issue by URL\n$ gh issue pin https://github.com/owner/repo/issues/23\n\n# Pin an issue to specific repository\n$ gh issue pin 23 --repo owner/repo"'
export def "gh issue pin" [
    number_or_url: string,
    --repo (-R): string,    # Select another repository using the `[HOST/]OWNER/REPO` format
]: nothing -> string {
    ^gh issue pin ...(nusage argv [$number_or_url] {--repo: $repo})
}

# Reopen issue
@usage 'flag "-c --comment" help="Add a reopening comment" {
            arg <COMMENT>
        }'
@usage 'arg <number-or-url>'
export def "gh issue reopen" [
    number_or_url: string,
    --repo (-R): string,     # Select another repository using the `[HOST/]OWNER/REPO` format
    --comment (-c): string,  # Add a reopening comment
]: nothing -> string {
    ^gh issue reopen ...(nusage argv [$number_or_url] {--repo: $repo, --comment: $comment})
}

# Show status of relevant issues
@usage 'flag "-q --jq" help="Filter JSON output using a jq `expression`" {
            arg <JQ>
        }'
@usage 'flag --json help="Output JSON with the specified `fields`" {
            arg <JSON>
        }'
@usage 'flag "-t --template" help="Format JSON output using a Go template; see \"gh help formatting\"" {
            arg <TEMPLATE>
        }'
export def "gh issue status" [
    --repo (-R): string,      # Select another repository using the `[HOST/]OWNER/REPO` format
    --jq (-q): string,        # Filter JSON output using a jq `expression`
    --json: string,           # Output JSON with the specified `fields`
    --template (-t): string,  # Format JSON output using a Go template; see "gh help formatting"
]: nothing -> string {
    ^gh issue status ...(nusage argv [] {
        --repo: $repo
        --jq: $jq
        --json: $json
        --template: $template
    })
}

# Transfer issue to another repository
@usage 'arg <number-or-url>'
@usage 'arg <destination-repo>'
export def "gh issue transfer" [
    number_or_url: string,
    destination_repo: string,
    --repo (-R): string,       # Select another repository using the `[HOST/]OWNER/REPO` format
]: nothing -> string {
    ^gh issue transfer ...(nusage argv [$number_or_url $destination_repo] {--repo: $repo})
}

# Unlock issue conversation
@usage 'arg <number-or-url>'
export def "gh issue unlock" [
    number_or_url: string,
    --repo (-R): string,    # Select another repository using the `[HOST/]OWNER/REPO` format
]: nothing -> string {
    ^gh issue unlock ...(nusage argv [$number_or_url] {--repo: $repo})
}

# Unpin an issue
#
# Unpin an issue from a repository.
#
# The issue can be specified by issue number or URL.
@usage 'long_help "Unpin an issue from a repository.\n\nThe issue can be specified by issue number or URL.\n"'
@usage 'arg <number-or-url>'
@usage 'example "# Unpin issue from the current repository\n$ gh issue unpin 23\n\n# Unpin issue by URL\n$ gh issue unpin https://github.com/owner/repo/issues/23\n\n# Unpin an issue from specific repository\n$ gh issue unpin 23 --repo owner/repo"'
export def "gh issue unpin" [
    number_or_url: string,
    --repo (-R): string,    # Select another repository using the `[HOST/]OWNER/REPO` format
]: nothing -> string {
    ^gh issue unpin ...(nusage argv [$number_or_url] {--repo: $repo})
}

# View an issue
#
# Display the title, body, and other information about an issue.
#
# When `--comments` is used, terminal output includes the issue details and comments.
# When output is piped or redirected, only the comments are printed.
#
# With `--web` flag, open the issue in a web browser instead.
@usage 'long_help "Display the title, body, and other information about an issue.\n\nWhen `--comments` is used, terminal output includes the issue details and comments.\nWhen output is piped or redirected, only the comments are printed.\n\nWith `--web` flag, open the issue in a web browser instead.\n"'
@usage 'flag "-c --comments" help="View issue comments"'
@usage 'flag "-q --jq" help="Filter JSON output using a jq `expression`" hide=#true {
            arg <JQ>
        }'
@usage 'flag --json help="Output JSON with the specified `fields`" {
            arg <JSON>
        }'
@usage 'flag "-t --template" help="Format JSON output using a Go template; see \"gh help formatting\"" hide=#true {
            arg <TEMPLATE>
        }'
@usage 'flag "-w --web" help="Open an issue in the browser" hide=#true'
@usage 'arg <number-or-url>'
@usage 'output "json" framing="json" { schema "{\n  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",\n  \"title\": \"An issue, as `gh issue view --json` selects its fields\",\n  \"$ref\": \"#/$defs/issue\",\n  \"$defs\": {\n    \"author\": {\n      \"type\": \"object\",\n      \"required\": [\"is_bot\", \"login\"],\n      \"additionalProperties\": false,\n      \"properties\": {\n        \"is_bot\": {\"type\": \"boolean\"},\n        \"login\": {\"type\": \"string\"},\n        \"id\": {\"type\": \"string\"},\n        \"name\": {\"type\": \"string\"}\n      }\n    },\n    \"label\": {\n      \"type\": \"object\",\n      \"required\": [\"id\", \"name\", \"description\", \"color\"],\n      \"additionalProperties\": false,\n      \"properties\": {\n        \"id\": {\"type\": \"string\"},\n        \"name\": {\"type\": \"string\"},\n        \"description\": {\"type\": \"string\"},\n        \"color\": {\"type\": \"string\"}\n      }\n    },\n    \"user\": {\n      \"type\": \"object\",\n      \"required\": [\"id\", \"login\", \"name\", \"databaseId\"],\n      \"additionalProperties\": false,\n      \"properties\": {\n        \"id\": {\"type\": \"string\"},\n        \"login\": {\"type\": \"string\"},\n        \"name\": {\"type\": \"string\"},\n        \"databaseId\": {\"type\": \"integer\"}\n      }\n    },\n    \"issue\": {\n      \"type\": \"object\",\n      \"required\": [\n        \"number\",\n        \"title\",\n        \"state\",\n        \"stateReason\",\n        \"url\",\n        \"author\",\n        \"createdAt\",\n        \"updatedAt\",\n        \"closedAt\",\n        \"labels\",\n        \"assignees\",\n        \"body\"\n      ],\n      \"additionalProperties\": false,\n      \"properties\": {\n        \"number\": {\"type\": \"integer\"},\n        \"title\": {\"type\": \"string\"},\n        \"state\": {\"enum\": [\"OPEN\", \"CLOSED\"]},\n        \"stateReason\": {\"type\": \"string\"},\n        \"url\": {\"type\": \"string\"},\n        \"author\": {\"$ref\": \"#/$defs/author\"},\n        \"createdAt\": {\"type\": \"string\", \"format\": \"date-time\"},\n        \"updatedAt\": {\"type\": \"string\", \"format\": \"date-time\"},\n        \"closedAt\": {\"anyOf\": [{\"type\": \"string\", \"format\": \"date-time\"}, {\"type\": \"null\"}]},\n        \"labels\": {\"type\": \"array\", \"items\": {\"$ref\": \"#/$defs/label\"}},\n        \"assignees\": {\"type\": \"array\", \"items\": {\"$ref\": \"#/$defs/user\"}},\n        \"body\": {\"type\": \"string\"}\n      }\n    }\n  }\n}\n" }'
export def "gh issue view" [
    number_or_url: string,
    --repo (-R): string,    # Select another repository using the `[HOST/]OWNER/REPO` format
    --comments (-c),        # View issue comments
]: nothing -> record<number: int, title: string, state: string, stateReason: string, url: string, author: record<is_bot: bool, login: string, id: oneof<string, nothing>, name: oneof<string, nothing>>, createdAt: datetime, updatedAt: datetime, closedAt: oneof<datetime, nothing>, labels: table<id: string, name: string, description: string, color: string>, assignees: table<id: string, login: string, name: string, databaseId: int>, body: string> {
    let text = ^gh issue view --json "number,title,state,stateReason,url,author,createdAt,updatedAt,closedAt,labels,assignees,body" ...(nusage argv [$number_or_url] {--repo: $repo, --comments: $comments})
    nusage decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"title\":\"An issue, as `gh issue view --json` selects its fields\",\"$ref\":\"#/$defs/issue\",\"$defs\":{\"author\":{\"type\":\"object\",\"required\":[\"is_bot\",\"login\"],\"additionalProperties\":false,\"properties\":{\"is_bot\":{\"type\":\"boolean\"},\"login\":{\"type\":\"string\"},\"id\":{\"type\":\"string\"},\"name\":{\"type\":\"string\"}}},\"label\":{\"type\":\"object\",\"required\":[\"id\",\"name\",\"description\",\"color\"],\"additionalProperties\":false,\"properties\":{\"id\":{\"type\":\"string\"},\"name\":{\"type\":\"string\"},\"description\":{\"type\":\"string\"},\"color\":{\"type\":\"string\"}}},\"user\":{\"type\":\"object\",\"required\":[\"id\",\"login\",\"name\",\"databaseId\"],\"additionalProperties\":false,\"properties\":{\"id\":{\"type\":\"string\"},\"login\":{\"type\":\"string\"},\"name\":{\"type\":\"string\"},\"databaseId\":{\"type\":\"integer\"}}},\"issue\":{\"type\":\"object\",\"required\":[\"number\",\"title\",\"state\",\"stateReason\",\"url\",\"author\",\"createdAt\",\"updatedAt\",\"closedAt\",\"labels\",\"assignees\",\"body\"],\"additionalProperties\":false,\"properties\":{\"number\":{\"type\":\"integer\"},\"title\":{\"type\":\"string\"},\"state\":{\"enum\":[\"OPEN\",\"CLOSED\"]},\"stateReason\":{\"type\":\"string\"},\"url\":{\"type\":\"string\"},\"author\":{\"$ref\":\"#/$defs/author\"},\"createdAt\":{\"type\":\"string\",\"format\":\"date-time\"},\"updatedAt\":{\"type\":\"string\",\"format\":\"date-time\"},\"closedAt\":{\"anyOf\":[{\"type\":\"string\",\"format\":\"date-time\"},{\"type\":\"null\"}]},\"labels\":{\"type\":\"array\",\"items\":{\"$ref\":\"#/$defs/label\"}},\"assignees\":{\"type\":\"array\",\"items\":{\"$ref\":\"#/$defs/user\"}},\"body\":{\"type\":\"string\"}}}}}" { from json | update author { default null id } | update author { default null name } | into datetime createdAt | into datetime updatedAt | update closedAt {|row| if $row.closedAt == null { null } else { $row.closedAt | into datetime } } }
}

# Manage pull requests
#
# Work with GitHub pull requests.
@usage 'long_help "Work with GitHub pull requests."'
@usage 'flag "-R --repo" help="Select another repository using the `[HOST/]OWNER/REPO` format" global=#true {
        arg <REPO>
    }'
@usage 'example "$ gh pr checkout 353\n$ gh pr create --fill\n$ gh pr view --web"'
export def "gh pr" [
    --repo (-R): string,  # Select another repository using the `[HOST/]OWNER/REPO` format
]: nothing -> string {
    ^gh pr ...(nusage argv [] {--repo: $repo})
}

# Check out a pull request in git
@usage 'alias co'
@usage 'flag "-b --branch" help="Local branch name to use (default [the name of the head branch])" {
            arg <BRANCH>
        }'
@usage 'flag --detach help="Checkout PR with a detached HEAD"'
@usage 'flag "-f --force" help="Reset the existing local branch to the latest state of the pull request"'
@usage 'flag --recurse-submodules help="Update all submodules after checkout"'
@usage 'flag --worktree help="Check out the pull request into a worktree at the given `path`" {
            arg <WORKTREE>
        }'
@usage 'arg "[number-or-url-or-branch]" required=#false'
@usage 'example "# Interactively select a PR from the 10 most recent to check out\n$ gh pr checkout\n\n# Checkout a specific PR\n$ gh pr checkout 32\n$ gh pr checkout https://github.com/OWNER/REPO/pull/32\n$ gh pr checkout feature\n$ gh pr checkout 32 --branch feature --worktree /path/to/wt-feature"'
export def "gh pr checkout" [
    number_or_url_or_branch?: string,
    --repo (-R): string,               # Select another repository using the `[HOST/]OWNER/REPO` format
    --branch (-b): string,             # Local branch name to use (default [the name of the head branch])
    --detach,                          # Checkout PR with a detached HEAD
    --force (-f),                      # Reset the existing local branch to the latest state of the pull request
    --recurse-submodules,              # Update all submodules after checkout
    --worktree: string,                # Check out the pull request into a worktree at the given `path`
]: nothing -> string {
    ^gh pr checkout ...(nusage argv [$number_or_url_or_branch] {
        --repo: $repo
        --branch: $branch
        --detach: $detach
        --force: $force
        --recurse-submodules: $recurse_submodules
        --worktree: $worktree
    })
}

# Show CI status for a single pull request
#
# Without an argument, the pull request that belongs to the current branch
# is selected.
#
# When the `--json` flag is used, it includes a `bucket` field, which categorizes
# the `state` field into `pass`, `fail`, `pending`, `skipping`, or `cancel`.
#
# Additional exit codes:
# 	8: Checks pending
@usage 'long_help "Show CI status for a single pull request.\n\nWithout an argument, the pull request that belongs to the current branch\nis selected.\n\nWhen the `--json` flag is used, it includes a `bucket` field, which categorizes\nthe `state` field into `pass`, `fail`, `pending`, `skipping`, or `cancel`.\n\nAdditional exit codes:\n\t8: Checks pending\n"'
@usage 'flag --fail-fast help="Exit watch mode on first check failure"'
@usage 'flag "-i --interval" help="Refresh interval in seconds in watch mode" default="10" {
            arg <INTERVAL>
        }'
@usage 'flag "-q --jq" help="Filter JSON output using a jq `expression`" hide=#true {
            arg <JQ>
        }'
@usage 'flag --json help="Output JSON with the specified `fields`" {
            arg <JSON>
        }'
@usage 'flag --required help="Only show checks that are required"'
@usage 'flag "-t --template" help="Format JSON output using a Go template; see \"gh help formatting\"" hide=#true {
            arg <TEMPLATE>
        }'
@usage 'flag --watch help="Watch checks until they finish" hide=#true'
@usage 'flag "-w --web" help="Open the web browser to show details about checks" hide=#true'
@usage 'arg "[number-or-url-or-branch]" required=#false'
@usage 'output "json" framing="json" { schema "{\n  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",\n  \"title\": \"The checks of a pull request, as `gh pr checks --json` selects their fields, one array\",\n  \"type\": \"array\",\n  \"items\": {\n    \"type\": \"object\",\n    \"required\": [\n      \"name\",\n      \"state\",\n      \"startedAt\",\n      \"completedAt\",\n      \"link\",\n      \"bucket\",\n      \"event\",\n      \"workflow\",\n      \"description\"\n    ],\n    \"additionalProperties\": false,\n    \"properties\": {\n      \"name\": {\"type\": \"string\"},\n      \"state\": {\"type\": \"string\"},\n      \"startedAt\": {\"type\": \"string\", \"format\": \"date-time\"},\n      \"completedAt\": {\"type\": \"string\", \"format\": \"date-time\"},\n      \"link\": {\"type\": \"string\"},\n      \"bucket\": {\"enum\": [\"pass\", \"fail\", \"pending\", \"skipping\", \"cancel\"]},\n      \"event\": {\"type\": \"string\"},\n      \"workflow\": {\"type\": \"string\"},\n      \"description\": {\"type\": \"string\"}\n    }\n  }\n}\n" }'
export def "gh pr checks" [
    number_or_url_or_branch?: string,
    --repo (-R): string,               # Select another repository using the `[HOST/]OWNER/REPO` format
    --fail-fast,                       # Exit watch mode on first check failure
    --interval (-i): string,           # Refresh interval in seconds in watch mode
    --required,                        # Only show checks that are required
]: nothing -> table<name: string, state: string, startedAt: datetime, completedAt: datetime, link: string, bucket: string, event: string, workflow: string, description: string> {
    let text = ^gh pr checks --json "name,state,startedAt,completedAt,link,bucket,event,workflow,description" ...(nusage argv [$number_or_url_or_branch] {
        --repo: $repo
        --fail-fast: $fail_fast
        --interval: $interval
        --required: $required
    })
    nusage decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"title\":\"The checks of a pull request, as `gh pr checks --json` selects their fields, one array\",\"type\":\"array\",\"items\":{\"type\":\"object\",\"required\":[\"name\",\"state\",\"startedAt\",\"completedAt\",\"link\",\"bucket\",\"event\",\"workflow\",\"description\"],\"additionalProperties\":false,\"properties\":{\"name\":{\"type\":\"string\"},\"state\":{\"type\":\"string\"},\"startedAt\":{\"type\":\"string\",\"format\":\"date-time\"},\"completedAt\":{\"type\":\"string\",\"format\":\"date-time\"},\"link\":{\"type\":\"string\"},\"bucket\":{\"enum\":[\"pass\",\"fail\",\"pending\",\"skipping\",\"cancel\"]},\"event\":{\"type\":\"string\"},\"workflow\":{\"type\":\"string\"},\"description\":{\"type\":\"string\"}}}}" { from json | into datetime startedAt | into datetime completedAt }
}

# Close a pull request
@usage 'flag "-c --comment" help="Leave a closing comment" {
            arg <COMMENT>
        }'
@usage 'flag "-d --delete-branch" help="Delete the local and remote branch after close"'
@usage 'arg <number-or-url-or-branch>'
export def "gh pr close" [
    number_or_url_or_branch: string,
    --repo (-R): string,              # Select another repository using the `[HOST/]OWNER/REPO` format
    --comment (-c): string,           # Leave a closing comment
    --delete-branch (-d),             # Delete the local and remote branch after close
]: nothing -> string {
    ^gh pr close ...(nusage argv [$number_or_url_or_branch] {--repo: $repo, --comment: $comment, --delete-branch: $delete_branch})
}

# Add a comment to a pull request
#
# Add a comment to a GitHub pull request.
#
# Without body text or attachments supplied through flags, the command will
# interactively prompt for the comment text.
#
# Use `--attach` to upload an image or video. If the body already references an
# attached file, such as `![alt](./login.png)`, that reference is rewritten to point
# at the uploaded asset. Paths in a `--body-file` are relative to its directory,
# falling back to the working directory. Any attached file the body does not reference
# is appended to the end of the comment.
# You can attach up to 50 files per command.
#
# Alt text for an image follows the path after `#`, as in
# `--attach './login.png#The login error state'`. Without it the filename is used.
# A reference already in the body keeps the alt text written there. Video renders
# as a player and has no alt text, so it cannot be given any.
@usage r#'long_help "Add a comment to a GitHub pull request.\n\nWithout body text or attachments supplied through flags, the command will\ninteractively prompt for the comment text.\n\nUse `--attach` to upload an image or video. If the body already references an\nattached file, such as `![alt](./login.png)`, that reference is rewritten to point\nat the uploaded asset. Paths in a `--body-file` are relative to its directory,\nfalling back to the working directory. Any attached file the body does not reference\nis appended to the end of the comment.\nYou can attach up to 50 files per command.\n\nAlt text for an image follows the path after `#`, as in\n`--attach './login.png#The login error state'`. Without it the filename is used.\nA reference already in the body keeps the alt text written there. Video renders\nas a player and has no alt text, so it cannot be given any.\n"'#
@usage r#'flag --attach help="Attach an image or video `file`, in '<file>#<image alt text>' format" {
            arg <ATTACH>
        }'#
@usage 'flag "-b --body" help="The comment body `text`" {
            arg <BODY>
        }'
@usage 'flag "-F --body-file" help="Read body text from `file` (use \"-\" to read from standard input)" {
            arg <BODY_FILE>
        }'
@usage 'flag --create-if-none help="Create a new comment if no comments are found. Can be used only with --edit-last"'
@usage 'flag --delete-last help="Delete the last comment of the current user"'
@usage 'flag --edit-last help="Edit the last comment of the current user"'
@usage 'flag "-e --editor" help="Skip prompts and open the text editor to write the body in"'
@usage 'flag "-w --web" help="Open the web browser to write the comment"'
@usage 'flag --yes help="Skip the delete confirmation prompt when --delete-last is provided"'
@usage 'arg "[number-or-url-or-branch]" required=#false'
@usage r#'example "# Add a comment to a pull request\n$ gh pr comment 13 --body \"Hi from GitHub CLI\"\n\n# Attach a screenshot, with alt text after \"#\"\n$ gh pr comment 13 --attach './login.png#The login error state'\n\n# Attach multiple files by repeating the flag\n$ gh pr comment 13 --attach ./before.png --attach ./after.png"'#
export def "gh pr comment" [
    number_or_url_or_branch?: string,
    --repo (-R): string,               # Select another repository using the `[HOST/]OWNER/REPO` format
    --attach: string,                  # Attach an image or video `file`, in '<file>#<image alt text>' format
    --body (-b): string,               # The comment body `text`
    --body-file (-F): string,          # Read body text from `file` (use "-" to read from standard input)
    --create-if-none,                  # Create a new comment if no comments are found. Can be used only with --edit-last
    --delete-last,                     # Delete the last comment of the current user
    --edit-last,                       # Edit the last comment of the current user
    --editor (-e),                     # Skip prompts and open the text editor to write the body in
    --web (-w),                        # Open the web browser to write the comment
    --yes,                             # Skip the delete confirmation prompt when --delete-last is provided
]: nothing -> string {
    ^gh pr comment ...(nusage argv [$number_or_url_or_branch] {
        --repo: $repo
        --attach: $attach
        --body: $body
        --body-file: $body_file
        --create-if-none: $create_if_none
        --delete-last: $delete_last
        --edit-last: $edit_last
        --editor: $editor
        --web: $web
        --yes: $yes
    })
}

# Create a pull request
#
# Create a pull request on GitHub.
#
# Upon success, the URL of the created pull request will be printed.
#
# When the current branch isn't fully pushed to a git remote, a prompt will ask where
# to push the branch and offer an option to fork the base repository. Any fork created this
# way will only have the default branch of the upstream repository. Use `--head` to
# explicitly skip any forking or pushing behavior.
#
# `--head` supports `<user>:<branch>` syntax to select a head repo owned by `<user>`.
# Using an organization as the `<user>` is currently not supported.
# For more information, see <https://github.com/cli/cli/issues/10093>
#
# A prompt will also ask for the title and the body of the pull request. Use `--title` and
# `--body` to skip this, or use `--fill` to autofill these values from git commits.
# It's important to notice that if the `--title` and/or `--body` are also provided
# alongside `--fill`, the values specified by `--title` and/or `--body` will
# take precedence and overwrite any autofilled content.
#
# The base branch for the created PR can be specified using the `--base` flag. If not provided,
# the value of `gh-merge-base` git branch config will be used. If not configured, the repository's
# default branch will be used. Run `git config branch.{current}.gh-merge-base {base}` to configure
# the current branch to use the specified merge base.
#
# Link an issue to the pull request by referencing the issue in the body of the pull
# request. If the body text mentions `Fixes #123` or `Closes #123`, the referenced issue
# will automatically get closed when the pull request gets merged.
#
# Use `--attach` to upload an image or video. The attachment is appended to the
# body. If the body references an attached file, such as `![alt](./login.png)`, that
# reference is rewritten to point at the uploaded asset instead. Paths in a
# `--body-file` are relative to its directory, falling back to the working directory.
# You can attach up to 50 files per command.
#
# Alt text for an image follows the path after `#`, as in
# `--attach './login.png#The login error state'`. Without it the filename is used.
# A reference already in the body keeps the alt text written there. Video renders
# as a player and has no alt text, so it cannot be given any.
#
# If some attachments upload and others fail, the pull request is still created with the
# ones that succeeded. The command then exits with a non-zero status, but the new pull
# request's URL is still printed to stdout.
#
# By default, users with write access to the base repository can push new commits to the
# head branch of the pull request. Disable this with `--no-maintainer-edit`.
#
# Adding a pull request to projects requires authorization with the `project` scope.
# To authorize, run `gh auth refresh -s project`.
@usage 'alias new'
@usage r#'long_help "Create a pull request on GitHub.\n\nUpon success, the URL of the created pull request will be printed.\n\nWhen the current branch isn't fully pushed to a git remote, a prompt will ask where\nto push the branch and offer an option to fork the base repository. Any fork created this\nway will only have the default branch of the upstream repository. Use `--head` to\nexplicitly skip any forking or pushing behavior.\n\n`--head` supports `<user>:<branch>` syntax to select a head repo owned by `<user>`.\nUsing an organization as the `<user>` is currently not supported.\nFor more information, see <https://github.com/cli/cli/issues/10093>\n\nA prompt will also ask for the title and the body of the pull request. Use `--title` and\n`--body` to skip this, or use `--fill` to autofill these values from git commits.\nIt's important to notice that if the `--title` and/or `--body` are also provided\nalongside `--fill`, the values specified by `--title` and/or `--body` will\ntake precedence and overwrite any autofilled content.\n\nThe base branch for the created PR can be specified using the `--base` flag. If not provided,\nthe value of `gh-merge-base` git branch config will be used. If not configured, the repository's\ndefault branch will be used. Run `git config branch.{current}.gh-merge-base {base}` to configure\nthe current branch to use the specified merge base.\n\nLink an issue to the pull request by referencing the issue in the body of the pull\nrequest. If the body text mentions `Fixes #123` or `Closes #123`, the referenced issue\nwill automatically get closed when the pull request gets merged.\n\nUse `--attach` to upload an image or video. The attachment is appended to the\nbody. If the body references an attached file, such as `![alt](./login.png)`, that\nreference is rewritten to point at the uploaded asset instead. Paths in a\n`--body-file` are relative to its directory, falling back to the working directory.\nYou can attach up to 50 files per command.\n\nAlt text for an image follows the path after `#`, as in\n`--attach './login.png#The login error state'`. Without it the filename is used.\nA reference already in the body keeps the alt text written there. Video renders\nas a player and has no alt text, so it cannot be given any.\n\nIf some attachments upload and others fail, the pull request is still created with the\nones that succeeded. The command then exits with a non-zero status, but the new pull\nrequest's URL is still printed to stdout.\n\nBy default, users with write access to the base repository can push new commits to the\nhead branch of the pull request. Disable this with `--no-maintainer-edit`.\n\nAdding a pull request to projects requires authorization with the `project` scope.\nTo authorize, run `gh auth refresh -s project`.\n"'#
@usage 'flag "-a --assignee" help="Assign people by their `login`. Use \"@me\" to self-assign." {
            arg <ASSIGNEE>
        }'
@usage r#'flag --attach help="Attach an image or video `file`, in '<file>#<image alt text>' format" {
            arg <ATTACH>
        }'#
@usage 'flag "-B --base" help="The `branch` into which you want your code merged" {
            arg <BASE>
        }'
@usage 'flag "-b --body" help="Body for the pull request" {
            arg <BODY>
        }'
@usage 'flag "-F --body-file" help="Read body text from `file` (use \"-\" to read from standard input)" {
            arg <BODY_FILE>
        }'
@usage 'flag "-d --draft" help="Mark pull request as a draft"'
@usage 'flag --dry-run help="Print details instead of creating the PR. May still push git changes."'
@usage 'flag "-e --editor" help="Skip prompts and open the text editor to write the title and body in. The first line is the title and the remaining text is the body."'
@usage 'flag "-f --fill" help="Use commit info for title and body"'
@usage 'flag --fill-first help="Use first commit info for title and body"'
@usage 'flag --fill-verbose help="Use commits msg+body for description"'
@usage 'flag "-H --head" help="The `branch` that contains commits for your pull request (default [current branch])" {
            arg <HEAD>
        }'
@usage 'flag "-l --label" help="Add labels by `name`" {
            arg <LABEL>
        }'
@usage 'flag "-m --milestone" help="Add the pull request to a milestone by `name`" {
            arg <MILESTONE>
        }'
@usage r#'flag --no-maintainer-edit help="Disable maintainer's ability to modify pull request"'#
@usage 'flag "-p --project" help="Add the pull request to projects by `title`" {
            arg <PROJECT>
        }'
@usage 'flag --recover help="Recover input from a failed run of create" {
            arg <RECOVER>
        }'
@usage 'flag "-r --reviewer" help="Request reviews from people or teams by their `handle`" {
            arg <REVIEWER>
        }'
@usage 'flag "-T --template" help="Template `file` to use as starting body text" {
            arg <TEMPLATE>
        }'
@usage 'flag "-t --title" help="Title for the pull request" {
            arg <TITLE>
        }'
@usage 'flag "-w --web" help="Open the web browser to create a pull request"'
@usage r#'example "$ gh pr create --title \"The bug is fixed\" --body \"Everything works again\"\n$ gh pr create --reviewer monalisa,hubot  --reviewer myorg/team-name\n$ gh pr create --project \"Roadmap\"\n$ gh pr create --base develop --head monalisa:feature\n$ gh pr create --template \"pull_request_template.md\"\n$ gh pr create --attach './login.png#The login error state'\n$ gh pr create --attach ./before.png --attach ./after.png"'#
export def "gh pr create" [
    --repo (-R): string,       # Select another repository using the `[HOST/]OWNER/REPO` format
    --assignee (-a): string,   # Assign people by their `login`. Use "@me" to self-assign.
    --attach: string,          # Attach an image or video `file`, in '<file>#<image alt text>' format
    --base (-B): string,       # The `branch` into which you want your code merged
    --body (-b): string,       # Body for the pull request
    --body-file (-F): string,  # Read body text from `file` (use "-" to read from standard input)
    --draft (-d),              # Mark pull request as a draft
    --dry-run,                 # Print details instead of creating the PR. May still push git changes.
    --editor (-e),             # Skip prompts and open the text editor to write the title and body in. The first line is the title and the remaining text is the body.
    --fill (-f),               # Use commit info for title and body
    --fill-first,              # Use first commit info for title and body
    --fill-verbose,            # Use commits msg+body for description
    --head (-H): string,       # The `branch` that contains commits for your pull request (default [current branch])
    --label (-l): string,      # Add labels by `name`
    --milestone (-m): string,  # Add the pull request to a milestone by `name`
    --no-maintainer-edit,      # Disable maintainer's ability to modify pull request
    --project (-p): string,    # Add the pull request to projects by `title`
    --recover: string,         # Recover input from a failed run of create
    --reviewer (-r): string,   # Request reviews from people or teams by their `handle`
    --template (-T): string,   # Template `file` to use as starting body text
    --title (-t): string,      # Title for the pull request
    --web (-w),                # Open the web browser to create a pull request
]: nothing -> string {
    ^gh pr create ...(nusage argv [] {
        --repo: $repo
        --assignee: $assignee
        --attach: $attach
        --base: $base
        --body: $body
        --body-file: $body_file
        --draft: $draft
        --dry-run: $dry_run
        --editor: $editor
        --fill: $fill
        --fill-first: $fill_first
        --fill-verbose: $fill_verbose
        --head: $head
        --label: $label
        --milestone: $milestone
        --no-maintainer-edit: $no_maintainer_edit
        --project: $project
        --recover: $recover
        --reviewer: $reviewer
        --template: $template
        --title: $title
        --web: $web
    })
}

# View changes in a pull request
#
# Without an argument, the pull request that belongs to the current branch
# is selected.
#
# With `--web` flag, open the pull request diff in a web browser instead.
#
# Use `--exclude` to filter out files matching a glob pattern. The pattern
# uses forward slashes as path separators on all platforms. You can repeat
# the flag to exclude multiple patterns.
#
# By default, terminal escape sequences in the diff are neutralized, since
# they could manipulate your terminal. Pass `--allow-escape-sequences` to
# print the diff verbatim, for example when piping a patch to another program.
@usage 'long_help "View changes in a pull request.\n\nWithout an argument, the pull request that belongs to the current branch\nis selected.\n\nWith `--web` flag, open the pull request diff in a web browser instead.\n\nUse `--exclude` to filter out files matching a glob pattern. The pattern\nuses forward slashes as path separators on all platforms. You can repeat\nthe flag to exclude multiple patterns.\n\nBy default, terminal escape sequences in the diff are neutralized, since\nthey could manipulate your terminal. Pass `--allow-escape-sequences` to\nprint the diff verbatim, for example when piping a patch to another program.\n"'
@usage 'flag --allow-escape-sequences help="Allow printing terminal escape sequences"'
@usage 'flag --color help="Use color in diff output: {always|never|auto}" default=auto {
            arg <COLOR>
        }'
@usage 'flag "-e --exclude" help="Exclude files matching glob `patterns` from the diff" {
            arg <EXCLUDE>
        }'
@usage 'flag --name-only help="Display only names of changed files"'
@usage 'flag --patch help="Display diff in patch format"'
@usage 'flag "-w --web" help="Open the pull request diff in the browser"'
@usage 'arg "[number-or-url-or-branch]" required=#false'
@usage r#'example "# See diff for current branch\n$ gh pr diff\n\n# See diff for a specific PR\n$ gh pr diff 123\n\n# Exclude files from diff output\n$ gh pr diff --exclude '*.yml' --exclude 'generated/*'\n\n# Exclude matching files by name\n$ gh pr diff --name-only --exclude '*.generated.*'"'#
export def "gh pr diff" [
    number_or_url_or_branch?: string,
    --repo (-R): string,               # Select another repository using the `[HOST/]OWNER/REPO` format
    --allow-escape-sequences,          # Allow printing terminal escape sequences
    --color: string,                   # Use color in diff output: {always|never|auto}
    --exclude (-e): string,            # Exclude files matching glob `patterns` from the diff
    --name-only,                       # Display only names of changed files
    --patch,                           # Display diff in patch format
    --web (-w),                        # Open the pull request diff in the browser
]: nothing -> string {
    ^gh pr diff ...(nusage argv [$number_or_url_or_branch] {
        --repo: $repo
        --allow-escape-sequences: $allow_escape_sequences
        --color: $color
        --exclude: $exclude
        --name-only: $name_only
        --patch: $patch
        --web: $web
    })
}

# Edit a pull request
#
# Without an argument, the pull request that belongs to the current branch
# is selected.
#
# Editing a pull request's projects requires authorization with the `project` scope.
# To authorize, run `gh auth refresh -s project`.
#
# Use `--attach` to upload an image or video. Without a body flag the pull
# request keeps the body it already has and the attachment is appended to it. If the
# body references an attached file, such as `![alt](./login.png)`, that reference
# is rewritten to point at the uploaded asset instead. Paths in a `--body-file` are
# relative to its directory, falling back to the working directory.
# You can attach up to 50 files per command.
#
# Alt text for an image follows the path after `#`, as in
# `--attach './login.png#The login error state'`. Without it the filename is used.
# A reference already in the body keeps the alt text written there. Video renders
# as a player and has no alt text, so it cannot be given any.
#
# If some attachments upload and others fail, the pull request is still updated with the
# ones that succeeded. The command then exits with a non-zero status, but the pull
# request's URL is still printed to stdout.
#
# The `--add-assignee` and `--remove-assignee` flags both support
# the following special values:
# - `@me`: assign or unassign yourself
# - `@copilot`: assign or unassign Copilot (not supported on GitHub Enterprise Server)
#
# The `--add-reviewer` and `--remove-reviewer` flags support
# the following special value:
# - `@copilot`: request or remove review from Copilot (not supported on GitHub Enterprise Server)
@usage r#'long_help "Edit a pull request.\n\nWithout an argument, the pull request that belongs to the current branch\nis selected.\n\nEditing a pull request's projects requires authorization with the `project` scope.\nTo authorize, run `gh auth refresh -s project`.\n\nUse `--attach` to upload an image or video. Without a body flag the pull\nrequest keeps the body it already has and the attachment is appended to it. If the\nbody references an attached file, such as `![alt](./login.png)`, that reference\nis rewritten to point at the uploaded asset instead. Paths in a `--body-file` are\nrelative to its directory, falling back to the working directory.\nYou can attach up to 50 files per command.\n\nAlt text for an image follows the path after `#`, as in\n`--attach './login.png#The login error state'`. Without it the filename is used.\nA reference already in the body keeps the alt text written there. Video renders\nas a player and has no alt text, so it cannot be given any.\n\nIf some attachments upload and others fail, the pull request is still updated with the\nones that succeeded. The command then exits with a non-zero status, but the pull\nrequest's URL is still printed to stdout.\n\nThe `--add-assignee` and `--remove-assignee` flags both support\nthe following special values:\n- `@me`: assign or unassign yourself\n- `@copilot`: assign or unassign Copilot (not supported on GitHub Enterprise Server)\n\nThe `--add-reviewer` and `--remove-reviewer` flags support\nthe following special value:\n- `@copilot`: request or remove review from Copilot (not supported on GitHub Enterprise Server)\n"'#
@usage 'flag --add-assignee help="Add assigned users by their `login`. Use \"@me\" to assign yourself, or \"@copilot\" to assign Copilot." {
            arg <ADD_ASSIGNEE>
        }'
@usage 'flag --add-label help="Add labels by `name`" {
            arg <ADD_LABEL>
        }'
@usage 'flag --add-project help="Add the pull request to projects by `title`" {
            arg <ADD_PROJECT>
        }'
@usage 'flag --add-reviewer help="Add or re-request reviewers by their `login`. Use \"@copilot\" to request review from Copilot." {
            arg <ADD_REVIEWER>
        }'
@usage r#'flag --attach help="Attach an image or video `file`, in '<file>#<image alt text>' format" {
            arg <ATTACH>
        }'#
@usage 'flag "-B --base" help="Change the base `branch` for this pull request" {
            arg <BASE>
        }'
@usage 'flag "-b --body" help="Set the new body." {
            arg <BODY>
        }'
@usage 'flag "-F --body-file" help="Read body text from `file` (use \"-\" to read from standard input)" {
            arg <BODY_FILE>
        }'
@usage 'flag "-m --milestone" help="Edit the milestone the pull request belongs to by `name`" {
            arg <MILESTONE>
        }'
@usage 'flag --remove-assignee help="Remove assigned users by their `login`. Use \"@me\" to unassign yourself, or \"@copilot\" to unassign Copilot." {
            arg <REMOVE_ASSIGNEE>
        }'
@usage 'flag --remove-label help="Remove labels by `name`" {
            arg <REMOVE_LABEL>
        }'
@usage 'flag --remove-milestone help="Remove the milestone association from the pull request"'
@usage 'flag --remove-project help="Remove the pull request from projects by `title`" {
            arg <REMOVE_PROJECT>
        }'
@usage 'flag --remove-reviewer help="Remove reviewers by their `login`. Use \"@copilot\" to remove review request from Copilot." {
            arg <REMOVE_REVIEWER>
        }'
@usage 'flag "-t --title" help="Set the new title." {
            arg <TITLE>
        }'
@usage 'arg "[number-or-url-or-branch]" required=#false'
@usage r#'example "# Edit the title and body of a pull request\n$ gh pr edit 23 --title \"I found a bug\" --body \"Nothing works\"\n\n# Use a file as the body\n$ gh pr edit 23 --body-file body.txt\n\n# Append a screenshot to the body, with alt text after \"#\"\n$ gh pr edit 23 --attach './login.png#The login error state'\n\n# Append multiple files by repeating the flag\n$ gh pr edit 23 --attach ./before.png --attach ./after.png\n\n# Manage labels\n$ gh pr edit 23 --add-label \"bug,help wanted\" --remove-label \"core\"\n\n# Manage reviewers\n$ gh pr edit 23 --add-reviewer monalisa,hubot --remove-reviewer myorg/team-name\n\n# Re-request review\n$ gh pr edit 23 --add-reviewer monalisa\n\n# Request a review from GitHub Copilot\n$ gh pr edit 23 --add-reviewer \"@copilot\"\n\n# Manage assignees\n$ gh pr edit 23 --add-assignee \"@me\" --remove-assignee monalisa,hubot\n\n# Assign GitHub Copilot\n$ gh pr edit 23 --add-assignee \"@copilot\"\n\n# Manage projects and milestones\n$ gh pr edit 23 --add-project \"Roadmap\" --remove-project v1,v2\n$ gh pr edit 23 --milestone \"Version 1\"\n$ gh pr edit 23 --remove-milestone"'#
export def "gh pr edit" [
    number_or_url_or_branch?: string,
    --repo (-R): string,               # Select another repository using the `[HOST/]OWNER/REPO` format
    --add-assignee: string,            # Add assigned users by their `login`. Use "@me" to assign yourself, or "@copilot" to assign Copilot.
    --add-label: string,               # Add labels by `name`
    --add-project: string,             # Add the pull request to projects by `title`
    --add-reviewer: string,            # Add or re-request reviewers by their `login`. Use "@copilot" to request review from Copilot.
    --attach: string,                  # Attach an image or video `file`, in '<file>#<image alt text>' format
    --base (-B): string,               # Change the base `branch` for this pull request
    --body (-b): string,               # Set the new body.
    --body-file (-F): string,          # Read body text from `file` (use "-" to read from standard input)
    --milestone (-m): string,          # Edit the milestone the pull request belongs to by `name`
    --remove-assignee: string,         # Remove assigned users by their `login`. Use "@me" to unassign yourself, or "@copilot" to unassign Copilot.
    --remove-label: string,            # Remove labels by `name`
    --remove-milestone,                # Remove the milestone association from the pull request
    --remove-project: string,          # Remove the pull request from projects by `title`
    --remove-reviewer: string,         # Remove reviewers by their `login`. Use "@copilot" to remove review request from Copilot.
    --title (-t): string,              # Set the new title.
]: nothing -> string {
    ^gh pr edit ...(nusage argv [$number_or_url_or_branch] {
        --repo: $repo
        --add-assignee: $add_assignee
        --add-label: $add_label
        --add-project: $add_project
        --add-reviewer: $add_reviewer
        --attach: $attach
        --base: $base
        --body: $body
        --body-file: $body_file
        --milestone: $milestone
        --remove-assignee: $remove_assignee
        --remove-label: $remove_label
        --remove-milestone: $remove_milestone
        --remove-project: $remove_project
        --remove-reviewer: $remove_reviewer
        --title: $title
    })
}

# List pull requests in a repository
#
# List pull requests in a GitHub repository. By default, this only lists open PRs.
#
# The search query syntax is documented here:
# <https://docs.github.com/en/search-github/searching-on-github/searching-issues-and-pull-requests>
#
# On supported GitHub hosts, advanced issue search syntax can be used in the
# `--search` query. For more information about advanced issue search, see:
# <https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/filtering-and-searching-issues-and-pull-requests#building-advanced-filters-for-issues>
@usage 'alias ls'
@usage 'long_help "List pull requests in a GitHub repository. By default, this only lists open PRs.\n\nThe search query syntax is documented here:\n<https://docs.github.com/en/search-github/searching-on-github/searching-issues-and-pull-requests>\n\nOn supported GitHub hosts, advanced issue search syntax can be used in the\n`--search` query. For more information about advanced issue search, see:\n<https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/filtering-and-searching-issues-and-pull-requests#building-advanced-filters-for-issues>\n"'
@usage 'flag --app help="Filter by GitHub App author" {
            arg <APP>
        }'
@usage 'flag "-a --assignee" help="Filter by assignee" {
            arg <ASSIGNEE>
        }'
@usage 'flag "-A --author" help="Filter by author (use --app to filter by a GitHub App)" {
            arg <AUTHOR>
        }'
@usage 'flag "-B --base" help="Filter by base branch" {
            arg <BASE>
        }'
@usage 'flag "-d --draft" help="Filter by draft state"'
@usage 'flag "-H --head" help="Filter by head branch (\"<owner>:<branch>\" syntax not supported)" {
            arg <HEAD>
        }'
@usage 'flag "-q --jq" help="Filter JSON output using a jq `expression`" hide=#true {
            arg <JQ>
        }'
@usage 'flag --json help="Output JSON with the specified `fields`" {
            arg <JSON>
        }'
@usage 'flag "-l --label" help="Filter by label" {
            arg <LABEL>
        }'
@usage 'flag "-L --limit" help="Maximum number of items to fetch" default="30" {
            arg <LIMIT>
        }'
@usage 'flag "-S --search" help="Search pull requests with `query`" {
            arg <SEARCH>
        }'
@usage 'flag "-s --state" help="Filter by state: {open|closed|merged|all}" default=open {
            arg <STATE>
        }'
@usage 'flag "-t --template" help="Format JSON output using a Go template; see \"gh help formatting\"" hide=#true {
            arg <TEMPLATE>
        }'
@usage 'flag "-w --web" help="List pull requests in the web browser" hide=#true'
@usage 'example "# List PRs authored by you\n$ gh pr list --author \"@me\"\n\n# List PRs opened by a GitHub App such as Dependabot\n$ gh pr list --app dependabot\n\n# List PRs with a specific head branch name\n$ gh pr list --head \"typo\"\n\n# List only PRs with all of the given labels\n$ gh pr list --label bug --label \"priority 1\"\n\n# Filter PRs using search syntax\n$ gh pr list --search \"status:success review:required\"\n\n# Find a PR that introduced a given commit\n$ gh pr list --search \"<SHA>\" --state merged"'
@usage 'output "json" framing="json" { schema "{\n  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",\n  \"title\": \"The pull requests `gh pr list --json` selects, one array\",\n  \"type\": \"array\",\n  \"items\": {\"$ref\": \"#/$defs/pull_request\"},\n  \"$defs\": {\n    \"author\": {\n      \"type\": \"object\",\n      \"required\": [\"is_bot\", \"login\"],\n      \"additionalProperties\": false,\n      \"properties\": {\n        \"is_bot\": {\"type\": \"boolean\"},\n        \"login\": {\"type\": \"string\"},\n        \"id\": {\"type\": \"string\"},\n        \"name\": {\"type\": \"string\"}\n      }\n    },\n    \"label\": {\n      \"type\": \"object\",\n      \"required\": [\"id\", \"name\", \"description\", \"color\"],\n      \"additionalProperties\": false,\n      \"properties\": {\n        \"id\": {\"type\": \"string\"},\n        \"name\": {\"type\": \"string\"},\n        \"description\": {\"type\": \"string\"},\n        \"color\": {\"type\": \"string\"}\n      }\n    },\n    \"pull_request\": {\n      \"type\": \"object\",\n      \"required\": [\n        \"number\",\n        \"title\",\n        \"state\",\n        \"isDraft\",\n        \"url\",\n        \"author\",\n        \"headRefName\",\n        \"baseRefName\",\n        \"createdAt\",\n        \"updatedAt\",\n        \"closedAt\",\n        \"mergedAt\",\n        \"labels\",\n        \"reviewDecision\",\n        \"body\"\n      ],\n      \"additionalProperties\": false,\n      \"properties\": {\n        \"number\": {\"type\": \"integer\"},\n        \"title\": {\"type\": \"string\"},\n        \"state\": {\"enum\": [\"OPEN\", \"CLOSED\", \"MERGED\"]},\n        \"isDraft\": {\"type\": \"boolean\"},\n        \"url\": {\"type\": \"string\"},\n        \"author\": {\"$ref\": \"#/$defs/author\"},\n        \"headRefName\": {\"type\": \"string\"},\n        \"baseRefName\": {\"type\": \"string\"},\n        \"createdAt\": {\"type\": \"string\", \"format\": \"date-time\"},\n        \"updatedAt\": {\"type\": \"string\", \"format\": \"date-time\"},\n        \"closedAt\": {\"anyOf\": [{\"type\": \"string\", \"format\": \"date-time\"}, {\"type\": \"null\"}]},\n        \"mergedAt\": {\"anyOf\": [{\"type\": \"string\", \"format\": \"date-time\"}, {\"type\": \"null\"}]},\n        \"labels\": {\"type\": \"array\", \"items\": {\"$ref\": \"#/$defs/label\"}},\n        \"reviewDecision\": {\"enum\": [\"\", \"APPROVED\", \"CHANGES_REQUESTED\", \"REVIEW_REQUIRED\"]},\n        \"body\": {\"type\": \"string\"}\n      }\n    }\n  }\n}\n" }'
export def "gh pr list" [
    --repo (-R): string,      # Select another repository using the `[HOST/]OWNER/REPO` format
    --app: string,            # Filter by GitHub App author
    --assignee (-a): string,  # Filter by assignee
    --author (-A): string,    # Filter by author (use --app to filter by a GitHub App)
    --base (-B): string,      # Filter by base branch
    --draft (-d),             # Filter by draft state
    --head (-H): string,      # Filter by head branch ("<owner>:<branch>" syntax not supported)
    --label (-l): string,     # Filter by label
    --limit (-L): string,     # Maximum number of items to fetch
    --search (-S): string,    # Search pull requests with `query`
    --state (-s): string,     # Filter by state: {open|closed|merged|all}
]: nothing -> table<number: int, title: string, state: string, isDraft: bool, url: string, author: record<is_bot: bool, login: string, id: oneof<string, nothing>, name: oneof<string, nothing>>, headRefName: string, baseRefName: string, createdAt: datetime, updatedAt: datetime, closedAt: oneof<datetime, nothing>, mergedAt: oneof<datetime, nothing>, labels: table<id: string, name: string, description: string, color: string>, reviewDecision: string, body: string> {
    let text = ^gh pr list --json "number,title,state,isDraft,url,author,headRefName,baseRefName,createdAt,updatedAt,closedAt,mergedAt,labels,reviewDecision,body" ...(nusage argv [] {
        --repo: $repo
        --app: $app
        --assignee: $assignee
        --author: $author
        --base: $base
        --draft: $draft
        --head: $head
        --label: $label
        --limit: $limit
        --search: $search
        --state: $state
    })
    nusage decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"title\":\"The pull requests `gh pr list --json` selects, one array\",\"type\":\"array\",\"items\":{\"$ref\":\"#/$defs/pull_request\"},\"$defs\":{\"author\":{\"type\":\"object\",\"required\":[\"is_bot\",\"login\"],\"additionalProperties\":false,\"properties\":{\"is_bot\":{\"type\":\"boolean\"},\"login\":{\"type\":\"string\"},\"id\":{\"type\":\"string\"},\"name\":{\"type\":\"string\"}}},\"label\":{\"type\":\"object\",\"required\":[\"id\",\"name\",\"description\",\"color\"],\"additionalProperties\":false,\"properties\":{\"id\":{\"type\":\"string\"},\"name\":{\"type\":\"string\"},\"description\":{\"type\":\"string\"},\"color\":{\"type\":\"string\"}}},\"pull_request\":{\"type\":\"object\",\"required\":[\"number\",\"title\",\"state\",\"isDraft\",\"url\",\"author\",\"headRefName\",\"baseRefName\",\"createdAt\",\"updatedAt\",\"closedAt\",\"mergedAt\",\"labels\",\"reviewDecision\",\"body\"],\"additionalProperties\":false,\"properties\":{\"number\":{\"type\":\"integer\"},\"title\":{\"type\":\"string\"},\"state\":{\"enum\":[\"OPEN\",\"CLOSED\",\"MERGED\"]},\"isDraft\":{\"type\":\"boolean\"},\"url\":{\"type\":\"string\"},\"author\":{\"$ref\":\"#/$defs/author\"},\"headRefName\":{\"type\":\"string\"},\"baseRefName\":{\"type\":\"string\"},\"createdAt\":{\"type\":\"string\",\"format\":\"date-time\"},\"updatedAt\":{\"type\":\"string\",\"format\":\"date-time\"},\"closedAt\":{\"anyOf\":[{\"type\":\"string\",\"format\":\"date-time\"},{\"type\":\"null\"}]},\"mergedAt\":{\"anyOf\":[{\"type\":\"string\",\"format\":\"date-time\"},{\"type\":\"null\"}]},\"labels\":{\"type\":\"array\",\"items\":{\"$ref\":\"#/$defs/label\"}},\"reviewDecision\":{\"enum\":[\"\",\"APPROVED\",\"CHANGES_REQUESTED\",\"REVIEW_REQUIRED\"]},\"body\":{\"type\":\"string\"}}}}}" { from json | update author { default null id } | update author { default null name } | into datetime createdAt | into datetime updatedAt | update closedAt {|row| if $row.closedAt == null { null } else { $row.closedAt | into datetime } } | update mergedAt {|row| if $row.mergedAt == null { null } else { $row.mergedAt | into datetime } } }
}

# Lock pull request conversation
@usage 'flag "-r --reason" help="Optional reason for locking conversation (off_topic, resolved, spam, too_heated)." {
            arg <REASON>
        }'
@usage 'arg <number-or-url>'
export def "gh pr lock" [
    number_or_url: string,
    --repo (-R): string,    # Select another repository using the `[HOST/]OWNER/REPO` format
    --reason (-r): string,  # Optional reason for locking conversation (off_topic, resolved, spam, too_heated).
]: nothing -> string {
    ^gh pr lock ...(nusage argv [$number_or_url] {--repo: $repo, --reason: $reason})
}

# Merge a pull request
#
# Merge a pull request on GitHub.
#
# Without an argument, the pull request that belongs to the current branch
# is selected.
#
# When targeting a branch that requires a merge queue, no merge strategy is required.
# If required checks have not yet passed, auto-merge will be enabled.
# If required checks have passed, the pull request will be added to the merge queue.
# To bypass a merge queue and merge directly, pass the `--admin` flag.
@usage 'long_help "Merge a pull request on GitHub.\n\nWithout an argument, the pull request that belongs to the current branch\nis selected.\n\nWhen targeting a branch that requires a merge queue, no merge strategy is required.\nIf required checks have not yet passed, auto-merge will be enabled.\nIf required checks have passed, the pull request will be added to the merge queue.\nTo bypass a merge queue and merge directly, pass the `--admin` flag.\n"'
@usage 'flag --admin help="Use administrator privileges to merge a pull request that does not meet requirements"'
@usage 'flag "-A --author-email" help="Email `text` for merge commit author" {
            arg <AUTHOR_EMAIL>
        }'
@usage 'flag --auto help="Automatically merge only after necessary requirements are met"'
@usage 'flag "-b --body" help="Body `text` for the merge commit" {
            arg <BODY>
        }'
@usage 'flag "-F --body-file" help="Read body text from `file` (use \"-\" to read from standard input)" {
            arg <BODY_FILE>
        }'
@usage 'flag "-d --delete-branch" help="Delete the local and remote branch after merge"'
@usage 'flag --disable-auto help="Disable auto-merge for this pull request"'
@usage 'flag --match-head-commit help="Commit `SHA` that the pull request head must match to allow merge" {
            arg <MATCH_HEAD_COMMIT>
        }'
@usage 'flag "-m --merge" help="Merge the commits with the base branch"'
@usage 'flag "-r --rebase" help="Rebase the commits onto the base branch"'
@usage 'flag "-s --squash" help="Squash the commits into one commit and merge it into the base branch"'
@usage 'flag "-t --subject" help="Subject `text` for the merge commit" {
            arg <SUBJECT>
        }'
@usage 'arg "[number-or-url-or-branch]" required=#false'
export def "gh pr merge" [
    number_or_url_or_branch?: string,
    --repo (-R): string,               # Select another repository using the `[HOST/]OWNER/REPO` format
    --admin,                           # Use administrator privileges to merge a pull request that does not meet requirements
    --author-email (-A): string,       # Email `text` for merge commit author
    --auto,                            # Automatically merge only after necessary requirements are met
    --body (-b): string,               # Body `text` for the merge commit
    --body-file (-F): string,          # Read body text from `file` (use "-" to read from standard input)
    --delete-branch (-d),              # Delete the local and remote branch after merge
    --disable-auto,                    # Disable auto-merge for this pull request
    --match-head-commit: string,       # Commit `SHA` that the pull request head must match to allow merge
    --merge (-m),                      # Merge the commits with the base branch
    --rebase (-r),                     # Rebase the commits onto the base branch
    --squash (-s),                     # Squash the commits into one commit and merge it into the base branch
    --subject (-t): string,            # Subject `text` for the merge commit
]: nothing -> string {
    ^gh pr merge ...(nusage argv [$number_or_url_or_branch] {
        --repo: $repo
        --admin: $admin
        --author-email: $author_email
        --auto: $auto
        --body: $body
        --body-file: $body_file
        --delete-branch: $delete_branch
        --disable-auto: $disable_auto
        --match-head-commit: $match_head_commit
        --merge: $merge
        --rebase: $rebase
        --squash: $squash
        --subject: $subject
    })
}

# Mark a pull request as ready for review
#
# Without an argument, the pull request that belongs to the current branch
# is marked as ready.
#
# If supported by your plan, convert to draft with `--undo`
@usage 'long_help "Mark a pull request as ready for review.\n\nWithout an argument, the pull request that belongs to the current branch\nis marked as ready.\n\nIf supported by your plan, convert to draft with `--undo`\n"'
@usage 'flag --undo help="Convert a pull request to \"draft\""'
@usage 'arg "[number-or-url-or-branch]" required=#false'
export def "gh pr ready" [
    number_or_url_or_branch?: string,
    --repo (-R): string,               # Select another repository using the `[HOST/]OWNER/REPO` format
    --undo,                            # Convert a pull request to "draft"
]: nothing -> string {
    ^gh pr ready ...(nusage argv [$number_or_url_or_branch] {--repo: $repo, --undo: $undo})
}

# Reopen a pull request
@usage 'flag "-c --comment" help="Add a reopening comment" {
            arg <COMMENT>
        }'
@usage 'arg <number-or-url-or-branch>'
export def "gh pr reopen" [
    number_or_url_or_branch: string,
    --repo (-R): string,              # Select another repository using the `[HOST/]OWNER/REPO` format
    --comment (-c): string,           # Add a reopening comment
]: nothing -> string {
    ^gh pr reopen ...(nusage argv [$number_or_url_or_branch] {--repo: $repo, --comment: $comment})
}

# Revert a pull request
@usage 'flag "-b --body" help="Body for the revert pull request" {
            arg <BODY>
        }'
@usage 'flag "-F --body-file" help="Read body text from `file` (use \"-\" to read from standard input)" {
            arg <BODY_FILE>
        }'
@usage 'flag "-d --draft" help="Mark revert pull request as a draft"'
@usage 'flag "-t --title" help="Title for the revert pull request" {
            arg <TITLE>
        }'
@usage 'arg <number-or-url-or-branch>'
export def "gh pr revert" [
    number_or_url_or_branch: string,
    --repo (-R): string,              # Select another repository using the `[HOST/]OWNER/REPO` format
    --body (-b): string,              # Body for the revert pull request
    --body-file (-F): string,         # Read body text from `file` (use "-" to read from standard input)
    --draft (-d),                     # Mark revert pull request as a draft
    --title (-t): string,             # Title for the revert pull request
]: nothing -> string {
    ^gh pr revert ...(nusage argv [$number_or_url_or_branch] {
        --repo: $repo
        --body: $body
        --body-file: $body_file
        --draft: $draft
        --title: $title
    })
}

# Add a review to a pull request
#
# Without an argument, the pull request that belongs to the current branch is reviewed.
@usage 'long_help "Add a review to a pull request.\n\nWithout an argument, the pull request that belongs to the current branch is reviewed.\n"'
@usage 'flag "-a --approve" help="Approve pull request"'
@usage 'flag "-b --body" help="Specify the body of a review" {
            arg <BODY>
        }'
@usage 'flag "-F --body-file" help="Read body text from `file` (use \"-\" to read from standard input)" {
            arg <BODY_FILE>
        }'
@usage 'flag "-c --comment" help="Comment on a pull request"'
@usage 'flag "-r --request-changes" help="Request changes on a pull request"'
@usage 'arg "[number-or-url-or-branch]" required=#false'
@usage 'example "# Approve the pull request of the current branch\n$ gh pr review --approve\n\n# Leave a review comment for the current branch\n$ gh pr review --comment -b \"interesting\"\n\n# Add a review for a specific pull request\n$ gh pr review 123\n\n# Request changes on a specific pull request\n$ gh pr review 123 -r -b \"needs more ASCII art\""'
export def "gh pr review" [
    number_or_url_or_branch?: string,
    --repo (-R): string,               # Select another repository using the `[HOST/]OWNER/REPO` format
    --approve (-a),                    # Approve pull request
    --body (-b): string,               # Specify the body of a review
    --body-file (-F): string,          # Read body text from `file` (use "-" to read from standard input)
    --comment (-c),                    # Comment on a pull request
    --request-changes (-r),            # Request changes on a pull request
]: nothing -> string {
    ^gh pr review ...(nusage argv [$number_or_url_or_branch] {
        --repo: $repo
        --approve: $approve
        --body: $body
        --body-file: $body_file
        --comment: $comment
        --request-changes: $request_changes
    })
}

# Show status of relevant pull requests
#
# The status shows a summary of pull requests that includes information such as
# pull request number, title, CI checks, reviews, etc.
#
# To see more details of CI checks, run `gh pr checks`.
@usage 'long_help "Show status of relevant pull requests.\n\nThe status shows a summary of pull requests that includes information such as\npull request number, title, CI checks, reviews, etc.\n\nTo see more details of CI checks, run `gh pr checks`.\n"'
@usage 'flag "-c --conflict-status" help="Display the merge conflict status of each pull request"'
@usage 'flag "-q --jq" help="Filter JSON output using a jq `expression`" {
            arg <JQ>
        }'
@usage 'flag --json help="Output JSON with the specified `fields`" {
            arg <JSON>
        }'
@usage 'flag "-t --template" help="Format JSON output using a Go template; see \"gh help formatting\"" {
            arg <TEMPLATE>
        }'
export def "gh pr status" [
    --repo (-R): string,      # Select another repository using the `[HOST/]OWNER/REPO` format
    --conflict-status (-c),   # Display the merge conflict status of each pull request
    --jq (-q): string,        # Filter JSON output using a jq `expression`
    --json: string,           # Output JSON with the specified `fields`
    --template (-t): string,  # Format JSON output using a Go template; see "gh help formatting"
]: nothing -> string {
    ^gh pr status ...(nusage argv [] {
        --repo: $repo
        --conflict-status: $conflict_status
        --jq: $jq
        --json: $json
        --template: $template
    })
}

# Unlock pull request conversation
@usage 'arg <number-or-url>'
export def "gh pr unlock" [
    number_or_url: string,
    --repo (-R): string,    # Select another repository using the `[HOST/]OWNER/REPO` format
]: nothing -> string {
    ^gh pr unlock ...(nusage argv [$number_or_url] {--repo: $repo})
}

# Update a pull request branch
#
# Update a pull request branch with latest changes of the base branch.
#
# Without an argument, the pull request that belongs to the current branch is selected.
#
# The default behavior is to update with a merge commit (i.e., merging the base branch
# into the PR's branch). To reconcile the changes with rebasing on top of the base
# branch, the `--rebase` option should be provided.
@usage r#'long_help "Update a pull request branch with latest changes of the base branch.\n\nWithout an argument, the pull request that belongs to the current branch is selected.\n\nThe default behavior is to update with a merge commit (i.e., merging the base branch\ninto the PR's branch). To reconcile the changes with rebasing on top of the base\nbranch, the `--rebase` option should be provided.\n"'#
@usage 'flag --rebase help="Update PR branch by rebasing on top of latest base branch"'
@usage 'arg "[number-or-url-or-branch]" required=#false'
@usage 'example "$ gh pr update-branch 23\n$ gh pr update-branch 23 --rebase\n$ gh pr update-branch 23 --repo owner/repo"'
export def "gh pr update-branch" [
    number_or_url_or_branch?: string,
    --repo (-R): string,               # Select another repository using the `[HOST/]OWNER/REPO` format
    --rebase,                          # Update PR branch by rebasing on top of latest base branch
]: nothing -> string {
    ^gh pr update-branch ...(nusage argv [$number_or_url_or_branch] {--repo: $repo, --rebase: $rebase})
}

# View a pull request
#
# Display the title, body, and other information about a pull request.
#
# Without an argument, the pull request that belongs to the current branch
# is displayed.
#
# When `--comments` is used, terminal output includes the pull request details, comments,
# and reviews. When output is piped or redirected, only comments and reviews are printed.
#
# With `--web` flag, open the pull request in a web browser instead.
@usage 'long_help "Display the title, body, and other information about a pull request.\n\nWithout an argument, the pull request that belongs to the current branch\nis displayed.\n\nWhen `--comments` is used, terminal output includes the pull request details, comments,\nand reviews. When output is piped or redirected, only comments and reviews are printed.\n\nWith `--web` flag, open the pull request in a web browser instead.\n"'
@usage 'flag "-c --comments" help="View pull request comments"'
@usage 'flag "-q --jq" help="Filter JSON output using a jq `expression`" hide=#true {
            arg <JQ>
        }'
@usage 'flag --json help="Output JSON with the specified `fields`" {
            arg <JSON>
        }'
@usage 'flag "-t --template" help="Format JSON output using a Go template; see \"gh help formatting\"" hide=#true {
            arg <TEMPLATE>
        }'
@usage 'flag "-w --web" help="Open a pull request in the browser" hide=#true'
@usage 'arg "[number-or-url-or-branch]" required=#false'
@usage 'output "json" framing="json" { schema "{\n  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",\n  \"title\": \"A pull request, as `gh pr view --json` selects its fields\",\n  \"$ref\": \"#/$defs/pull_request\",\n  \"$defs\": {\n    \"author\": {\n      \"type\": \"object\",\n      \"required\": [\"is_bot\", \"login\"],\n      \"additionalProperties\": false,\n      \"properties\": {\n        \"is_bot\": {\"type\": \"boolean\"},\n        \"login\": {\"type\": \"string\"},\n        \"id\": {\"type\": \"string\"},\n        \"name\": {\"type\": \"string\"}\n      }\n    },\n    \"label\": {\n      \"type\": \"object\",\n      \"required\": [\"id\", \"name\", \"description\", \"color\"],\n      \"additionalProperties\": false,\n      \"properties\": {\n        \"id\": {\"type\": \"string\"},\n        \"name\": {\"type\": \"string\"},\n        \"description\": {\"type\": \"string\"},\n        \"color\": {\"type\": \"string\"}\n      }\n    },\n    \"pull_request\": {\n      \"type\": \"object\",\n      \"required\": [\n        \"number\",\n        \"title\",\n        \"state\",\n        \"isDraft\",\n        \"url\",\n        \"author\",\n        \"headRefName\",\n        \"baseRefName\",\n        \"createdAt\",\n        \"updatedAt\",\n        \"closedAt\",\n        \"mergedAt\",\n        \"labels\",\n        \"reviewDecision\",\n        \"body\"\n      ],\n      \"additionalProperties\": false,\n      \"properties\": {\n        \"number\": {\"type\": \"integer\"},\n        \"title\": {\"type\": \"string\"},\n        \"state\": {\"enum\": [\"OPEN\", \"CLOSED\", \"MERGED\"]},\n        \"isDraft\": {\"type\": \"boolean\"},\n        \"url\": {\"type\": \"string\"},\n        \"author\": {\"$ref\": \"#/$defs/author\"},\n        \"headRefName\": {\"type\": \"string\"},\n        \"baseRefName\": {\"type\": \"string\"},\n        \"createdAt\": {\"type\": \"string\", \"format\": \"date-time\"},\n        \"updatedAt\": {\"type\": \"string\", \"format\": \"date-time\"},\n        \"closedAt\": {\"anyOf\": [{\"type\": \"string\", \"format\": \"date-time\"}, {\"type\": \"null\"}]},\n        \"mergedAt\": {\"anyOf\": [{\"type\": \"string\", \"format\": \"date-time\"}, {\"type\": \"null\"}]},\n        \"labels\": {\"type\": \"array\", \"items\": {\"$ref\": \"#/$defs/label\"}},\n        \"reviewDecision\": {\"enum\": [\"\", \"APPROVED\", \"CHANGES_REQUESTED\", \"REVIEW_REQUIRED\"]},\n        \"body\": {\"type\": \"string\"}\n      }\n    }\n  }\n}\n" }'
export def "gh pr view" [
    number_or_url_or_branch?: string,
    --repo (-R): string,               # Select another repository using the `[HOST/]OWNER/REPO` format
    --comments (-c),                   # View pull request comments
]: nothing -> record<number: int, title: string, state: string, isDraft: bool, url: string, author: record<is_bot: bool, login: string, id: oneof<string, nothing>, name: oneof<string, nothing>>, headRefName: string, baseRefName: string, createdAt: datetime, updatedAt: datetime, closedAt: oneof<datetime, nothing>, mergedAt: oneof<datetime, nothing>, labels: table<id: string, name: string, description: string, color: string>, reviewDecision: string, body: string> {
    let text = ^gh pr view --json "number,title,state,isDraft,url,author,headRefName,baseRefName,createdAt,updatedAt,closedAt,mergedAt,labels,reviewDecision,body" ...(nusage argv [$number_or_url_or_branch] {--repo: $repo, --comments: $comments})
    nusage decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"title\":\"A pull request, as `gh pr view --json` selects its fields\",\"$ref\":\"#/$defs/pull_request\",\"$defs\":{\"author\":{\"type\":\"object\",\"required\":[\"is_bot\",\"login\"],\"additionalProperties\":false,\"properties\":{\"is_bot\":{\"type\":\"boolean\"},\"login\":{\"type\":\"string\"},\"id\":{\"type\":\"string\"},\"name\":{\"type\":\"string\"}}},\"label\":{\"type\":\"object\",\"required\":[\"id\",\"name\",\"description\",\"color\"],\"additionalProperties\":false,\"properties\":{\"id\":{\"type\":\"string\"},\"name\":{\"type\":\"string\"},\"description\":{\"type\":\"string\"},\"color\":{\"type\":\"string\"}}},\"pull_request\":{\"type\":\"object\",\"required\":[\"number\",\"title\",\"state\",\"isDraft\",\"url\",\"author\",\"headRefName\",\"baseRefName\",\"createdAt\",\"updatedAt\",\"closedAt\",\"mergedAt\",\"labels\",\"reviewDecision\",\"body\"],\"additionalProperties\":false,\"properties\":{\"number\":{\"type\":\"integer\"},\"title\":{\"type\":\"string\"},\"state\":{\"enum\":[\"OPEN\",\"CLOSED\",\"MERGED\"]},\"isDraft\":{\"type\":\"boolean\"},\"url\":{\"type\":\"string\"},\"author\":{\"$ref\":\"#/$defs/author\"},\"headRefName\":{\"type\":\"string\"},\"baseRefName\":{\"type\":\"string\"},\"createdAt\":{\"type\":\"string\",\"format\":\"date-time\"},\"updatedAt\":{\"type\":\"string\",\"format\":\"date-time\"},\"closedAt\":{\"anyOf\":[{\"type\":\"string\",\"format\":\"date-time\"},{\"type\":\"null\"}]},\"mergedAt\":{\"anyOf\":[{\"type\":\"string\",\"format\":\"date-time\"},{\"type\":\"null\"}]},\"labels\":{\"type\":\"array\",\"items\":{\"$ref\":\"#/$defs/label\"}},\"reviewDecision\":{\"enum\":[\"\",\"APPROVED\",\"CHANGES_REQUESTED\",\"REVIEW_REQUIRED\"]},\"body\":{\"type\":\"string\"}}}}}" { from json | update author { default null id } | update author { default null name } | into datetime createdAt | into datetime updatedAt | update closedAt {|row| if $row.closedAt == null { null } else { $row.closedAt | into datetime } } | update mergedAt {|row| if $row.mergedAt == null { null } else { $row.mergedAt | into datetime } } }
}

# Manage releases
@usage 'flag "-R --repo" help="Select another repository using the `[HOST/]OWNER/REPO` format" global=#true {
        arg <REPO>
    }'
export def "gh release" [
    --repo (-R): string,  # Select another repository using the `[HOST/]OWNER/REPO` format
]: nothing -> string {
    ^gh release ...(nusage argv [] {--repo: $repo})
}

# Create a new release
#
# Create a new GitHub Release for a repository.
#
# A list of asset files may be given to upload to the new release. To define a
# display label for an asset, append text starting with `#` after the file name.
#
# If a matching git tag does not yet exist, one will automatically get created
# from the latest state of the default branch.
# Use `--target` to point to a different branch or commit for the automatic tag creation.
# Use `--verify-tag` to abort the release if the tag doesn't already exist.
# To fetch the new tag locally after the release, do `git fetch --tags origin`.
#
# To create a release from an annotated git tag, first create one locally with
# git, push the tag to GitHub, then run this command.
# Use `--notes-from-tag` to get the release notes from the annotated git tag.
# If the tag is not annotated, the commit message will be used instead.
#
# Use `--generate-notes` to automatically generate notes using GitHub Release Notes API.
# When using automatically generated release notes, a release title will also be automatically
# generated unless a title was explicitly passed. Additional release notes can be prepended to
# automatically generated notes by using the `--notes` flag.
#
# By default, the release is created even if there are no new commits since the last release.
# This may result in the same or duplicate release which may not be desirable in some cases.
# Use `--fail-on-no-commits` to fail if no new commits are available. This flag has no
# effect if there are no existing releases or this is the very first release.
#
# ## Immutable Releases
#
# When release immutability is enabled for a repository, the following protections are enforced:
# - Git tags associated with a release cannot be modified or deleted.
# - Release assets cannot be modified or deleted.
#
# When you attach assets, `gh release create` creates a draft release, uploads
# each asset, and then publishes the release. These steps use separate API requests
# and do not form a single atomic operation. If you specify `--draft`, the command
# leaves the release unpublished.
#
# When release immutability is enabled for the repository, its protections take effect
# only when the release is published. While the release remains a draft, users and
# workflows with the required permissions can modify it and its assets, including while
# this command is running.
@usage 'alias new'
@usage r#'long_help "Create a new GitHub Release for a repository.\n\nA list of asset files may be given to upload to the new release. To define a\ndisplay label for an asset, append text starting with `#` after the file name.\n\nIf a matching git tag does not yet exist, one will automatically get created\nfrom the latest state of the default branch.\nUse `--target` to point to a different branch or commit for the automatic tag creation.\nUse `--verify-tag` to abort the release if the tag doesn't already exist.\nTo fetch the new tag locally after the release, do `git fetch --tags origin`.\n\nTo create a release from an annotated git tag, first create one locally with\ngit, push the tag to GitHub, then run this command.\nUse `--notes-from-tag` to get the release notes from the annotated git tag.\nIf the tag is not annotated, the commit message will be used instead.\n\nUse `--generate-notes` to automatically generate notes using GitHub Release Notes API.\nWhen using automatically generated release notes, a release title will also be automatically\ngenerated unless a title was explicitly passed. Additional release notes can be prepended to\nautomatically generated notes by using the `--notes` flag.\n\nBy default, the release is created even if there are no new commits since the last release.\nThis may result in the same or duplicate release which may not be desirable in some cases.\nUse `--fail-on-no-commits` to fail if no new commits are available. This flag has no\neffect if there are no existing releases or this is the very first release.\n\n## Immutable Releases\n\nWhen release immutability is enabled for a repository, the following protections are enforced:\n- Git tags associated with a release cannot be modified or deleted.\n- Release assets cannot be modified or deleted.\n\nWhen you attach assets, `gh release create` creates a draft release, uploads\neach asset, and then publishes the release. These steps use separate API requests\nand do not form a single atomic operation. If you specify `--draft`, the command\nleaves the release unpublished.\n\nWhen release immutability is enabled for the repository, its protections take effect\nonly when the release is published. While the release remains a draft, users and\nworkflows with the required permissions can modify it and its assets, including while\nthis command is running.\n"'#
@usage 'flag --discussion-category help="Start a discussion in the specified category" {
            arg <DISCUSSION_CATEGORY>
        }'
@usage 'flag "-d --draft" help="Save the release as a draft instead of publishing it"'
@usage 'flag --fail-on-no-commits help="Fail if there are no commits since the last release (no impact on the first release)"'
@usage 'flag --generate-notes help="Automatically generate title and notes for the release via GitHub Release Notes API"'
@usage 'flag --latest help="Mark this release as \"Latest\" (default [automatic based on date and version]). --latest=false to explicitly NOT set as latest"'
@usage 'flag "-n --notes" help="Release notes" {
            arg <NOTES>
        }'
@usage 'flag "-F --notes-file" help="Read release notes from `file` (use \"-\" to read from standard input)" {
            arg <NOTES_FILE>
        }'
@usage 'flag --notes-from-tag help="Fetch notes from the tag annotation or message of commit associated with tag"'
@usage 'flag --notes-start-tag help="Tag to use as the starting point for generating release notes" {
            arg <NOTES_START_TAG>
        }'
@usage 'flag "-p --prerelease" help="Mark the release as a prerelease"'
@usage 'flag --target help="Target `branch` or full commit SHA (default [main branch])" {
            arg <TARGET>
        }'
@usage 'flag "-t --title" help="Release title" {
            arg <TITLE>
        }'
@usage r#'flag --verify-tag help="Abort in case the git tag doesn't already exist in the remote repository"'#
@usage 'arg "[tag]" required=#false'
@usage 'arg "[filename-or-pattern]…" required=#false var=#true'
@usage r#'example "# Interactively create a release\n$ gh release create\n\n# Interactively create a release from specific tag\n$ gh release create v1.2.3\n\n# Non-interactively create a release\n$ gh release create v1.2.3 --notes \"bugfix release\"\n\n# Use automatically generated via GitHub Release Notes API release notes\n$ gh release create v1.2.3 --generate-notes\n\n# Use release notes from a file\n$ gh release create v1.2.3 -F release-notes.md\n\n# Use tag annotation or associated commit message as notes\n$ gh release create v1.2.3 --notes-from-tag\n\n# Don't mark the release as latest\n$ gh release create v1.2.3 --latest=false\n\n# Upload all tarballs in a directory as release assets\n$ gh release create v1.2.3 ./dist/*.tgz\n\n# Upload a release asset with a display label\n$ gh release create v1.2.3 '/path/to/asset.zip#My display label'\n\n# Create a release and start a discussion\n$ gh release create v1.2.3 --discussion-category \"General\"\n\n# Create a release only if there are new commits available since the last release\n$ gh release create v1.2.3 --fail-on-no-commits"'#
export def "gh release create" [
    tag?: string,
    ...filename_or_pattern: string,
    --repo (-R): string,             # Select another repository using the `[HOST/]OWNER/REPO` format
    --discussion-category: string,   # Start a discussion in the specified category
    --draft (-d),                    # Save the release as a draft instead of publishing it
    --fail-on-no-commits,            # Fail if there are no commits since the last release (no impact on the first release)
    --generate-notes,                # Automatically generate title and notes for the release via GitHub Release Notes API
    --latest,                        # Mark this release as "Latest" (default [automatic based on date and version]). --latest=false to explicitly NOT set as latest
    --notes (-n): string,            # Release notes
    --notes-file (-F): string,       # Read release notes from `file` (use "-" to read from standard input)
    --notes-from-tag,                # Fetch notes from the tag annotation or message of commit associated with tag
    --notes-start-tag: string,       # Tag to use as the starting point for generating release notes
    --prerelease (-p),               # Mark the release as a prerelease
    --target: string,                # Target `branch` or full commit SHA (default [main branch])
    --title (-t): string,            # Release title
    --verify-tag,                    # Abort in case the git tag doesn't already exist in the remote repository
]: nothing -> string {
    ^gh release create ...(nusage argv [$tag ...$filename_or_pattern] {
        --repo: $repo
        --discussion-category: $discussion_category
        --draft: $draft
        --fail-on-no-commits: $fail_on_no_commits
        --generate-notes: $generate_notes
        --latest: $latest
        --notes: $notes
        --notes-file: $notes_file
        --notes-from-tag: $notes_from_tag
        --notes-start-tag: $notes_start_tag
        --prerelease: $prerelease
        --target: $target
        --title: $title
        --verify-tag: $verify_tag
    })
}

# Delete a release
@usage 'flag --cleanup-tag help="Delete the specified tag in addition to its release"'
@usage 'flag "-y --yes" help="Skip the confirmation prompt"'
@usage 'arg <tag>'
export def "gh release delete" [
    tag: string,
    --repo (-R): string,  # Select another repository using the `[HOST/]OWNER/REPO` format
    --cleanup-tag,        # Delete the specified tag in addition to its release
    --yes (-y),           # Skip the confirmation prompt
]: nothing -> string {
    ^gh release delete ...(nusage argv [$tag] {--repo: $repo, --cleanup-tag: $cleanup_tag, --yes: $yes})
}

# Delete an asset from a release
@usage 'flag "-y --yes" help="Skip the confirmation prompt"'
@usage 'arg <tag>'
@usage 'arg <asset-name>'
export def "gh release delete-asset" [
    tag: string,
    asset_name: string,
    --repo (-R): string,  # Select another repository using the `[HOST/]OWNER/REPO` format
    --yes (-y),           # Skip the confirmation prompt
]: nothing -> string {
    ^gh release delete-asset ...(nusage argv [$tag $asset_name] {--repo: $repo, --yes: $yes})
}

# Download release assets
#
# Download assets from a GitHub release.
#
# Without an explicit tag name argument, assets are downloaded from the
# latest release in the project. In this case, `--pattern` or `--archive`
# is required.
@usage 'long_help "Download assets from a GitHub release.\n\nWithout an explicit tag name argument, assets are downloaded from the\nlatest release in the project. In this case, `--pattern` or `--archive`\nis required.\n"'
@usage 'flag --allow-escape-sequences help="Allow printing terminal escape sequences when writing an asset to standard output"'
@usage 'flag "-A --archive" help="Download the source code archive in the specified `format` (zip or tar.gz)" {
            arg <ARCHIVE>
        }'
@usage 'flag --clobber help="Overwrite existing files of the same name"'
@usage 'flag "-D --dir" help="The `directory` to download files into" default="." {
            arg <DIR>
        }'
@usage 'flag "-O --output" help="The `file` to write a single asset to (use \"-\" to write to standard output)" {
            arg <OUTPUT>
        }'
@usage 'flag "-p --pattern" help="Download only assets that match a glob pattern" {
            arg <PATTERN>
        }'
@usage 'flag --skip-existing help="Skip downloading when files of the same name exist"'
@usage 'arg "[tag]" required=#false'
@usage r#'example "# Download all assets from a specific release\n$ gh release download v1.2.3\n\n# Download only Debian packages for the latest release\n$ gh release download --pattern '*.deb'\n\n# Specify multiple file patterns\n$ gh release download -p '*.deb' -p '*.rpm'\n\n# Download the archive of the source code for a release\n$ gh release download v1.2.3 --archive=zip"'#
export def "gh release download" [
    tag?: string,
    --repo (-R): string,       # Select another repository using the `[HOST/]OWNER/REPO` format
    --allow-escape-sequences,  # Allow printing terminal escape sequences when writing an asset to standard output
    --archive (-A): string,    # Download the source code archive in the specified `format` (zip or tar.gz)
    --clobber,                 # Overwrite existing files of the same name
    --dir (-D): string,        # The `directory` to download files into
    --output (-O): string,     # The `file` to write a single asset to (use "-" to write to standard output)
    --pattern (-p): string,    # Download only assets that match a glob pattern
    --skip-existing,           # Skip downloading when files of the same name exist
]: nothing -> string {
    ^gh release download ...(nusage argv [$tag] {
        --repo: $repo
        --allow-escape-sequences: $allow_escape_sequences
        --archive: $archive
        --clobber: $clobber
        --dir: $dir
        --output: $output
        --pattern: $pattern
        --skip-existing: $skip_existing
    })
}

# Edit a release
@usage 'flag --discussion-category help="Start a discussion in the specified category when publishing a draft" {
            arg <DISCUSSION_CATEGORY>
        }'
@usage 'flag --draft help="Save the release as a draft instead of publishing it"'
@usage 'flag --latest help="Explicitly mark the release as \"Latest\""'
@usage 'flag "-n --notes" help="Release notes" {
            arg <NOTES>
        }'
@usage 'flag "-F --notes-file" help="Read release notes from `file` (use \"-\" to read from standard input)" {
            arg <NOTES_FILE>
        }'
@usage 'flag --prerelease help="Mark the release as a prerelease"'
@usage 'flag --tag help="The name of the tag" {
            arg <TAG>
        }'
@usage 'flag --target help="Target `branch` or full commit SHA (default [main branch])" {
            arg <TARGET>
        }'
@usage 'flag "-t --title" help="Release title" {
            arg <TITLE>
        }'
@usage r#'flag --verify-tag help="Abort in case the git tag doesn't already exist in the remote repository"'#
@usage 'arg <tag>'
@usage 'example "# Publish a release that was previously a draft\n$ gh release edit v1.0 --draft=false\n\n# Update the release notes from the content of a file\n$ gh release edit v1.0 --notes-file /path/to/release_notes.md"'
export def "gh release edit" [
    tag: string,
    --repo (-R): string,            # Select another repository using the `[HOST/]OWNER/REPO` format
    --discussion-category: string,  # Start a discussion in the specified category when publishing a draft
    --draft,                        # Save the release as a draft instead of publishing it
    --latest,                       # Explicitly mark the release as "Latest"
    --notes (-n): string,           # Release notes
    --notes-file (-F): string,      # Read release notes from `file` (use "-" to read from standard input)
    --prerelease,                   # Mark the release as a prerelease
    --tag: string,                  # The name of the tag
    --target: string,               # Target `branch` or full commit SHA (default [main branch])
    --title (-t): string,           # Release title
    --verify-tag,                   # Abort in case the git tag doesn't already exist in the remote repository
]: nothing -> string {
    ^gh release edit ...(nusage argv [$tag] {
        --repo: $repo
        --discussion-category: $discussion_category
        --draft: $draft
        --latest: $latest
        --notes: $notes
        --notes-file: $notes_file
        --prerelease: $prerelease
        --tag: $tag
        --target: $target
        --title: $title
        --verify-tag: $verify_tag
    })
}

# List releases in a repository
@usage 'alias ls'
@usage 'flag --exclude-drafts help="Exclude draft releases"'
@usage 'flag --exclude-pre-releases help="Exclude pre-releases"'
@usage 'flag "-q --jq" help="Filter JSON output using a jq `expression`" hide=#true {
            arg <JQ>
        }'
@usage 'flag --json help="Output JSON with the specified `fields`" {
            arg <JSON>
        }'
@usage 'flag "-L --limit" help="Maximum number of items to fetch" default="30" {
            arg <LIMIT>
        }'
@usage 'flag "-O --order" help="Order of releases returned: {asc|desc}" default=desc {
            arg <ORDER>
        }'
@usage 'flag "-t --template" help="Format JSON output using a Go template; see \"gh help formatting\"" hide=#true {
            arg <TEMPLATE>
        }'
@usage 'output "json" framing="json" { schema "{\n  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",\n  \"title\": \"The releases `gh release list --json` selects, one array\",\n  \"type\": \"array\",\n  \"items\": {\n    \"type\": \"object\",\n    \"required\": [\n      \"name\",\n      \"tagName\",\n      \"isDraft\",\n      \"isLatest\",\n      \"isPrerelease\",\n      \"isImmutable\",\n      \"createdAt\",\n      \"publishedAt\"\n    ],\n    \"additionalProperties\": false,\n    \"properties\": {\n      \"name\": {\"type\": \"string\"},\n      \"tagName\": {\"type\": \"string\"},\n      \"isDraft\": {\"type\": \"boolean\"},\n      \"isLatest\": {\"type\": \"boolean\"},\n      \"isPrerelease\": {\"type\": \"boolean\"},\n      \"isImmutable\": {\"type\": \"boolean\"},\n      \"createdAt\": {\"type\": \"string\", \"format\": \"date-time\"},\n      \"publishedAt\": {\"type\": \"string\", \"format\": \"date-time\"}\n    }\n  }\n}\n" }'
export def "gh release list" [
    --repo (-R): string,     # Select another repository using the `[HOST/]OWNER/REPO` format
    --exclude-drafts,        # Exclude draft releases
    --exclude-pre-releases,  # Exclude pre-releases
    --limit (-L): string,    # Maximum number of items to fetch
    --order (-O): string,    # Order of releases returned: {asc|desc}
]: nothing -> table<name: string, tagName: string, isDraft: bool, isLatest: bool, isPrerelease: bool, isImmutable: bool, createdAt: datetime, publishedAt: datetime> {
    let text = ^gh release list --json "name,tagName,isDraft,isLatest,isPrerelease,isImmutable,createdAt,publishedAt" ...(nusage argv [] {
        --repo: $repo
        --exclude-drafts: $exclude_drafts
        --exclude-pre-releases: $exclude_pre_releases
        --limit: $limit
        --order: $order
    })
    nusage decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"title\":\"The releases `gh release list --json` selects, one array\",\"type\":\"array\",\"items\":{\"type\":\"object\",\"required\":[\"name\",\"tagName\",\"isDraft\",\"isLatest\",\"isPrerelease\",\"isImmutable\",\"createdAt\",\"publishedAt\"],\"additionalProperties\":false,\"properties\":{\"name\":{\"type\":\"string\"},\"tagName\":{\"type\":\"string\"},\"isDraft\":{\"type\":\"boolean\"},\"isLatest\":{\"type\":\"boolean\"},\"isPrerelease\":{\"type\":\"boolean\"},\"isImmutable\":{\"type\":\"boolean\"},\"createdAt\":{\"type\":\"string\",\"format\":\"date-time\"},\"publishedAt\":{\"type\":\"string\",\"format\":\"date-time\"}}}}" { from json | into datetime createdAt | into datetime publishedAt }
}

# Upload assets to a release
#
# Upload asset files to a GitHub Release.
#
# To define a display label for an asset, append text starting with `#` after the
# file name.
#
# When using `--clobber`, existing assets are deleted before new assets are uploaded.
# If the upload fails, the original assets will be lost.
@usage 'long_help "Upload asset files to a GitHub Release.\n\nTo define a display label for an asset, append text starting with `#` after the\nfile name.\n\nWhen using `--clobber`, existing assets are deleted before new assets are uploaded.\nIf the upload fails, the original assets will be lost.\n"'
@usage 'flag --clobber help="Delete and re-upload existing assets of the same name"'
@usage 'arg <tag>'
@usage 'arg <files>… var=#true'
export def "gh release upload" [
    tag: string,
    ...files: string,
    --repo (-R): string,  # Select another repository using the `[HOST/]OWNER/REPO` format
    --clobber,            # Delete and re-upload existing assets of the same name
]: nothing -> string {
    ^gh release upload ...(nusage argv [$tag ...$files] {--repo: $repo, --clobber: $clobber})
}

# View information about a release
#
# View information about a GitHub Release.
#
# Without an explicit tag name argument, the latest release in the project
# is shown.
@usage 'long_help "View information about a GitHub Release.\n\nWithout an explicit tag name argument, the latest release in the project\nis shown.\n"'
@usage 'flag "-q --jq" help="Filter JSON output using a jq `expression`" hide=#true {
            arg <JQ>
        }'
@usage 'flag --json help="Output JSON with the specified `fields`" {
            arg <JSON>
        }'
@usage 'flag "-t --template" help="Format JSON output using a Go template; see \"gh help formatting\"" hide=#true {
            arg <TEMPLATE>
        }'
@usage 'flag "-w --web" help="Open the release in the browser" hide=#true'
@usage 'arg "[tag]" required=#false'
@usage 'output "json" framing="json" { schema "{\n  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",\n  \"title\": \"A release with its assets, as `gh release view --json` selects its fields\",\n  \"type\": \"object\",\n  \"required\": [\n    \"tagName\",\n    \"name\",\n    \"body\",\n    \"isDraft\",\n    \"isPrerelease\",\n    \"isImmutable\",\n    \"createdAt\",\n    \"publishedAt\",\n    \"targetCommitish\",\n    \"url\",\n    \"author\",\n    \"assets\"\n  ],\n  \"additionalProperties\": false,\n  \"properties\": {\n    \"tagName\": {\"type\": \"string\"},\n    \"name\": {\"type\": \"string\"},\n    \"body\": {\"type\": \"string\"},\n    \"isDraft\": {\"type\": \"boolean\"},\n    \"isPrerelease\": {\"type\": \"boolean\"},\n    \"isImmutable\": {\"type\": \"boolean\"},\n    \"createdAt\": {\"type\": \"string\", \"format\": \"date-time\"},\n    \"publishedAt\": {\"anyOf\": [{\"type\": \"string\", \"format\": \"date-time\"}, {\"type\": \"null\"}]},\n    \"targetCommitish\": {\"type\": \"string\"},\n    \"url\": {\"type\": \"string\"},\n    \"author\": {\n      \"type\": \"object\",\n      \"required\": [\"id\", \"login\"],\n      \"additionalProperties\": false,\n      \"properties\": {\n        \"id\": {\"type\": \"string\"},\n        \"login\": {\"type\": \"string\"}\n      }\n    },\n    \"assets\": {\n      \"type\": \"array\",\n      \"items\": {\n        \"type\": \"object\",\n        \"required\": [\n          \"url\",\n          \"apiUrl\",\n          \"id\",\n          \"name\",\n          \"label\",\n          \"size\",\n          \"digest\",\n          \"state\",\n          \"createdAt\",\n          \"updatedAt\",\n          \"downloadCount\",\n          \"contentType\"\n        ],\n        \"additionalProperties\": false,\n        \"properties\": {\n          \"url\": {\"type\": \"string\"},\n          \"apiUrl\": {\"type\": \"string\"},\n          \"id\": {\"type\": \"string\"},\n          \"name\": {\"type\": \"string\"},\n          \"label\": {\"type\": \"string\"},\n          \"size\": {\"type\": \"integer\"},\n          \"digest\": {\"type\": [\"string\", \"null\"]},\n          \"state\": {\"type\": \"string\"},\n          \"createdAt\": {\"type\": \"string\", \"format\": \"date-time\"},\n          \"updatedAt\": {\"type\": \"string\", \"format\": \"date-time\"},\n          \"downloadCount\": {\"type\": \"integer\"},\n          \"contentType\": {\"type\": \"string\"}\n        }\n      }\n    }\n  }\n}\n" }'
export def "gh release view" [
    tag?: string,
    --repo (-R): string,  # Select another repository using the `[HOST/]OWNER/REPO` format
]: nothing -> record<tagName: string, name: string, body: string, isDraft: bool, isPrerelease: bool, isImmutable: bool, createdAt: datetime, publishedAt: oneof<datetime, nothing>, targetCommitish: string, url: string, author: record<id: string, login: string>, assets: table<url: string, apiUrl: string, id: string, name: string, label: string, size: int, digest: oneof<string, nothing>, state: string, createdAt: datetime, updatedAt: datetime, downloadCount: int, contentType: string>> {
    let text = ^gh release view --json "tagName,name,body,isDraft,isPrerelease,isImmutable,createdAt,publishedAt,targetCommitish,url,author,assets" ...(nusage argv [$tag] {--repo: $repo})
    nusage decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"title\":\"A release with its assets, as `gh release view --json` selects its fields\",\"type\":\"object\",\"required\":[\"tagName\",\"name\",\"body\",\"isDraft\",\"isPrerelease\",\"isImmutable\",\"createdAt\",\"publishedAt\",\"targetCommitish\",\"url\",\"author\",\"assets\"],\"additionalProperties\":false,\"properties\":{\"tagName\":{\"type\":\"string\"},\"name\":{\"type\":\"string\"},\"body\":{\"type\":\"string\"},\"isDraft\":{\"type\":\"boolean\"},\"isPrerelease\":{\"type\":\"boolean\"},\"isImmutable\":{\"type\":\"boolean\"},\"createdAt\":{\"type\":\"string\",\"format\":\"date-time\"},\"publishedAt\":{\"anyOf\":[{\"type\":\"string\",\"format\":\"date-time\"},{\"type\":\"null\"}]},\"targetCommitish\":{\"type\":\"string\"},\"url\":{\"type\":\"string\"},\"author\":{\"type\":\"object\",\"required\":[\"id\",\"login\"],\"additionalProperties\":false,\"properties\":{\"id\":{\"type\":\"string\"},\"login\":{\"type\":\"string\"}}},\"assets\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"required\":[\"url\",\"apiUrl\",\"id\",\"name\",\"label\",\"size\",\"digest\",\"state\",\"createdAt\",\"updatedAt\",\"downloadCount\",\"contentType\"],\"additionalProperties\":false,\"properties\":{\"url\":{\"type\":\"string\"},\"apiUrl\":{\"type\":\"string\"},\"id\":{\"type\":\"string\"},\"name\":{\"type\":\"string\"},\"label\":{\"type\":\"string\"},\"size\":{\"type\":\"integer\"},\"digest\":{\"type\":[\"string\",\"null\"]},\"state\":{\"type\":\"string\"},\"createdAt\":{\"type\":\"string\",\"format\":\"date-time\"},\"updatedAt\":{\"type\":\"string\",\"format\":\"date-time\"},\"downloadCount\":{\"type\":\"integer\"},\"contentType\":{\"type\":\"string\"}}}}}}" { from json | into datetime createdAt | update publishedAt {|row| if $row.publishedAt == null { null } else { $row.publishedAt | into datetime } } | update assets {|row| $row.assets | into datetime createdAt } | update assets {|row| $row.assets | into datetime updatedAt } }
}

# Manage repositories
#
# Work with GitHub repositories.
@usage 'long_help "Work with GitHub repositories."'
@usage 'example "$ gh repo create\n$ gh repo clone cli/cli\n$ gh repo view --web"'
export def "gh repo" []: nothing -> string {
    ^gh repo ...(nusage argv [] {})
}

# Archive a repository
#
# Archive a GitHub repository.
#
# With no argument, archives the current repository.
@usage 'long_help "Archive a GitHub repository.\n\nWith no argument, archives the current repository."'
@usage 'flag --confirm help="Skip the confirmation prompt" hide=#true deprecated="use `--yes` instead"'
@usage 'flag "-y --yes" help="Skip the confirmation prompt"'
@usage 'arg "[repository]" required=#false'
export def "gh repo archive" [
    repository?: string,
    --yes (-y),           # Skip the confirmation prompt
]: nothing -> string {
    ^gh repo archive ...(nusage argv [$repository] {--yes: $yes})
}

# Manage autolink references
#
# Autolinks link issues, pull requests, commit messages, and release descriptions to external third-party services.
#
# Autolinks require `admin` role to view or manage.
#
# For more information, see <https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/configuring-autolinks-to-reference-external-resources>
@usage 'long_help "Autolinks link issues, pull requests, commit messages, and release descriptions to external third-party services.\n\nAutolinks require `admin` role to view or manage.\n\nFor more information, see <https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/configuring-autolinks-to-reference-external-resources>\n"'
@usage 'flag "-R --repo" help="Select another repository using the `[HOST/]OWNER/REPO` format" global=#true {
            arg <REPO>
        }'
export def "gh repo autolink" [
    --repo (-R): string,  # Select another repository using the `[HOST/]OWNER/REPO` format
]: nothing -> string {
    ^gh repo autolink ...(nusage argv [] {--repo: $repo})
}

# Create a new autolink reference
#
# Create a new autolink reference for a repository.
#
# The `keyPrefix` argument specifies the prefix that will generate a link when it is appended by certain characters.
#
# The `urlTemplate` argument specifies the target URL that will be generated when the keyPrefix is found, which
# must contain `<num>` variable for the reference number.
#
# By default, autolinks are alphanumeric with `--numeric` flag used to create a numeric autolink.
#
# The `<num>` variable behavior differs depending on whether the autolink is alphanumeric or numeric:
#
# - alphanumeric: matches `A-Z` (case insensitive), `0-9`, and `-`
# - numeric: matches `0-9`
#
# If the template contains multiple instances of `<num>`, only the first will be replaced.
@usage 'alias new'
@usage 'long_help "Create a new autolink reference for a repository.\n\nThe `keyPrefix` argument specifies the prefix that will generate a link when it is appended by certain characters.\n\nThe `urlTemplate` argument specifies the target URL that will be generated when the keyPrefix is found, which\nmust contain `<num>` variable for the reference number.\n\nBy default, autolinks are alphanumeric with `--numeric` flag used to create a numeric autolink.\n\nThe `<num>` variable behavior differs depending on whether the autolink is alphanumeric or numeric:\n\n- alphanumeric: matches `A-Z` (case insensitive), `0-9`, and `-`\n- numeric: matches `0-9`\n\nIf the template contains multiple instances of `<num>`, only the first will be replaced.\n"'
@usage 'flag "-n --numeric" help="Mark autolink as numeric"'
@usage 'arg <keyPrefix>'
@usage 'arg <urlTemplate>'
@usage 'example "# Create an alphanumeric autolink to example.com for the key prefix \"TICKET-\".\n# Generates https://example.com/TICKET?query=123abc from \"TICKET-123abc\".\n$ gh repo autolink create TICKET- \"https://example.com/TICKET?query=<num>\"\n\n# Create a numeric autolink to example.com for the key prefix \"STORY-\".\n# Generates https://example.com/STORY?id=123 from \"STORY-123\".\n$ gh repo autolink create STORY- \"https://example.com/STORY?id=<num>\" --numeric"'
export def "gh repo autolink create" [
    keyprefix: string,
    urltemplate: string,
    --repo (-R): string,  # Select another repository using the `[HOST/]OWNER/REPO` format
    --numeric (-n),       # Mark autolink as numeric
]: nothing -> string {
    ^gh repo autolink create ...(nusage argv [$keyprefix $urltemplate] {--repo: $repo, --numeric: $numeric})
}

# Delete an autolink reference
#
# Delete an autolink reference for a repository.
@usage 'long_help "Delete an autolink reference for a repository."'
@usage 'flag --yes help="Confirm deletion without prompting"'
@usage 'arg <id>'
export def "gh repo autolink delete" [
    id: string,
    --repo (-R): string,  # Select another repository using the `[HOST/]OWNER/REPO` format
    --yes,                # Confirm deletion without prompting
]: nothing -> string {
    ^gh repo autolink delete ...(nusage argv [$id] {--repo: $repo, --yes: $yes})
}

# List autolink references for a GitHub repository
#
# Gets all autolink references that are configured for a repository.
#
# Information about autolinks is only available to repository administrators.
@usage 'alias ls'
@usage 'long_help "Gets all autolink references that are configured for a repository.\n\nInformation about autolinks is only available to repository administrators.\n"'
@usage 'flag "-q --jq" help="Filter JSON output using a jq `expression`" {
                arg <JQ>
            }'
@usage 'flag --json help="Output JSON with the specified `fields`" {
                arg <JSON>
            }'
@usage 'flag "-t --template" help="Format JSON output using a Go template; see \"gh help formatting\"" {
                arg <TEMPLATE>
            }'
@usage 'flag "-w --web" help="List autolink references in the web browser"'
export def "gh repo autolink list" [
    --repo (-R): string,      # Select another repository using the `[HOST/]OWNER/REPO` format
    --jq (-q): string,        # Filter JSON output using a jq `expression`
    --json: string,           # Output JSON with the specified `fields`
    --template (-t): string,  # Format JSON output using a Go template; see "gh help formatting"
    --web (-w),               # List autolink references in the web browser
]: nothing -> string {
    ^gh repo autolink list ...(nusage argv [] {
        --repo: $repo
        --jq: $jq
        --json: $json
        --template: $template
        --web: $web
    })
}

# View an autolink reference
#
# View an autolink reference for a repository.
@usage 'long_help "View an autolink reference for a repository."'
@usage 'flag "-q --jq" help="Filter JSON output using a jq `expression`" {
                arg <JQ>
            }'
@usage 'flag --json help="Output JSON with the specified `fields`" {
                arg <JSON>
            }'
@usage 'flag "-t --template" help="Format JSON output using a Go template; see \"gh help formatting\"" {
                arg <TEMPLATE>
            }'
@usage 'arg <id>'
export def "gh repo autolink view" [
    id: string,
    --repo (-R): string,      # Select another repository using the `[HOST/]OWNER/REPO` format
    --jq (-q): string,        # Filter JSON output using a jq `expression`
    --json: string,           # Output JSON with the specified `fields`
    --template (-t): string,  # Format JSON output using a Go template; see "gh help formatting"
]: nothing -> string {
    ^gh repo autolink view ...(nusage argv [$id] {
        --repo: $repo
        --jq: $jq
        --json: $json
        --template: $template
    })
}

# Clone a repository locally
#
# Clone a GitHub repository locally. Pass additional `git clone` flags by listing
# them after `--`.
#
# If the `OWNER/` portion of the `OWNER/REPO` repository argument is omitted, it
# defaults to the name of the authenticating user.
#
# When a protocol scheme is not provided in the repository argument, the `git_protocol` will be
# chosen from your configuration, which can be checked via `gh config get git_protocol`. If the protocol
# scheme is provided, the repository will be cloned using the specified protocol.
#
# If the repository is a fork, its parent repository will be added as an additional
# git remote called `upstream`. The remote name can be configured using `--upstream-remote-name`.
# The `--upstream-remote-name` option supports an `@owner` value which will name
# the remote after the owner of the parent repository.
#
# If the repository is a fork, its parent repository will be set as the default remote repository.
# To skip this behavior, use `--no-upstream`.
@usage 'long_help "Clone a GitHub repository locally. Pass additional `git clone` flags by listing\nthem after `--`.\n\nIf the `OWNER/` portion of the `OWNER/REPO` repository argument is omitted, it\ndefaults to the name of the authenticating user.\n\nWhen a protocol scheme is not provided in the repository argument, the `git_protocol` will be\nchosen from your configuration, which can be checked via `gh config get git_protocol`. If the protocol\nscheme is provided, the repository will be cloned using the specified protocol.\n\nIf the repository is a fork, its parent repository will be added as an additional\ngit remote called `upstream`. The remote name can be configured using `--upstream-remote-name`.\nThe `--upstream-remote-name` option supports an `@owner` value which will name\nthe remote after the owner of the parent repository.\n\nIf the repository is a fork, its parent repository will be set as the default remote repository.\nTo skip this behavior, use `--no-upstream`.\n"'
@usage 'flag --no-upstream help="Do not add an upstream remote when cloning a fork"'
@usage 'flag "-u --upstream-remote-name" help="Upstream remote name when cloning a fork" default=upstream {
            arg <UPSTREAM_REMOTE_NAME>
        }'
@usage 'arg <repository>'
@usage 'arg "[directory]" required=#false'
@usage 'example "# Clone a repository from a specific org\n$ gh repo clone cli/cli\n\n# Clone a repository from your own account\n$ gh repo clone myrepo\n\n# Clone a repo, overriding git protocol configuration\n$ gh repo clone https://github.com/cli/cli\n$ gh repo clone git@github.com:cli/cli.git\n\n# Clone a repository to a custom directory\n$ gh repo clone cli/cli workspace/cli\n\n# Clone a repository with additional git clone flags\n$ gh repo clone cli/cli -- --depth=1\n\n# Clone a fork without adding an upstream remote\n$ gh repo clone myfork --no-upstream"'
export def "gh repo clone" [
    repository: string,
    directory?: string,
    --no-upstream,                        # Do not add an upstream remote when cloning a fork
    --upstream-remote-name (-u): string,  # Upstream remote name when cloning a fork
]: nothing -> string {
    ^gh repo clone ...(nusage argv [$repository $directory] {--no-upstream: $no_upstream, --upstream-remote-name: $upstream_remote_name})
}

# Create a new repository
#
# Create a new GitHub repository.
#
# To create a repository interactively, use `gh repo create` with no arguments.
#
# To create a remote repository non-interactively, supply the repository name and one of `--public`, `--private`, or `--internal`.
# Pass `--clone` to clone the new repository locally.
#
# If the `OWNER/` portion of the `OWNER/REPO` name argument is omitted, it
# defaults to the name of the authenticating user.
#
# To create a remote repository from an existing local repository, specify the source directory with `--source`.
# By default, the remote repository name will be the name of the source directory.
#
# Pass `--push` to push any local commits to the new repository. If the repo is bare, this will mirror all refs.
#
# For language or platform .gitignore templates to use with `--gitignore`, <https://github.com/github/gitignore>.
#
# For license keywords to use with `--license`, run `gh repo license list` or visit <https://choosealicense.com>.
#
# The repo is created with the configured repository default branch, see <https://docs.github.com/en/account-and-profile/setting-up-and-managing-your-personal-account-on-github/managing-user-account-settings/managing-the-default-branch-name-for-your-repositories>.
@usage 'alias new'
@usage 'long_help "Create a new GitHub repository.\n\nTo create a repository interactively, use `gh repo create` with no arguments.\n\nTo create a remote repository non-interactively, supply the repository name and one of `--public`, `--private`, or `--internal`.\nPass `--clone` to clone the new repository locally.\n\nIf the `OWNER/` portion of the `OWNER/REPO` name argument is omitted, it\ndefaults to the name of the authenticating user.\n\nTo create a remote repository from an existing local repository, specify the source directory with `--source`.\nBy default, the remote repository name will be the name of the source directory.\n\nPass `--push` to push any local commits to the new repository. If the repo is bare, this will mirror all refs.\n\nFor language or platform .gitignore templates to use with `--gitignore`, <https://github.com/github/gitignore>.\n\nFor license keywords to use with `--license`, run `gh repo license list` or visit <https://choosealicense.com>.\n\nThe repo is created with the configured repository default branch, see <https://docs.github.com/en/account-and-profile/setting-up-and-managing-your-personal-account-on-github/managing-user-account-settings/managing-the-default-branch-name-for-your-repositories>.\n"'
@usage 'flag --add-readme help="Add a README file to the new repository"'
@usage 'flag "-c --clone" help="Clone the new repository to the current directory"'
@usage 'flag "-y --confirm" help="Skip the confirmation prompt" hide=#true deprecated="Pass any argument to skip confirmation prompt"'
@usage 'flag "-d --description" help="Description of the repository" {
            arg <DESCRIPTION>
        }'
@usage 'flag --disable-issues help="Disable issues in the new repository"'
@usage 'flag --disable-wiki help="Disable wiki in the new repository"'
@usage 'flag --enable-issues help="Enable issues in the new repository" hide=#true deprecated="Disable issues with `--disable-issues`" default="true"'
@usage 'flag --enable-wiki help="Enable wiki in the new repository" hide=#true deprecated="Disable wiki with `--disable-wiki`" default="true"'
@usage 'flag "-g --gitignore" help="Specify a gitignore template for the repository" {
            arg <GITIGNORE>
        }'
@usage 'flag "-h --homepage" help="Repository home page `URL`" {
            arg <HOMEPAGE>
        }'
@usage 'flag --include-all-branches help="Include all branches from template repository"'
@usage 'flag --internal help="Make the new repository internal"'
@usage 'flag "-l --license" help="Specify an Open Source License for the repository" {
            arg <LICENSE>
        }'
@usage 'flag --private help="Make the new repository private"'
@usage 'flag --public help="Make the new repository public"'
@usage 'flag --push help="Push local commits to the new repository"'
@usage 'flag "-r --remote" help="Specify remote name for the new repository" {
            arg <REMOTE>
        }'
@usage 'flag "-s --source" help="Specify path to local repository to use as source" {
            arg <SOURCE>
        }'
@usage 'flag "-t --team" help="The `name` of the organization team to be granted access" {
            arg <TEAM>
        }'
@usage 'flag "-p --template" help="Make the new repository based on a template `repository`" {
            arg <TEMPLATE>
        }'
@usage 'arg "[name]" required=#false'
@usage 'example "# Create a repository interactively\n$ gh repo create\n\n# Create a new remote repository and clone it locally\n$ gh repo create my-project --public --clone\n\n# Create a new remote repository in a different organization\n$ gh repo create my-org/my-project --public\n\n# Create a remote repository from the current directory\n$ gh repo create my-project --private --source=. --remote=upstream"'
export def "gh repo create" [
    name?: string,
    --add-readme,                # Add a README file to the new repository
    --clone (-c),                # Clone the new repository to the current directory
    --description (-d): string,  # Description of the repository
    --disable-issues,            # Disable issues in the new repository
    --disable-wiki,              # Disable wiki in the new repository
    --gitignore (-g): string,    # Specify a gitignore template for the repository
    --homepage (-h): string,     # Repository home page `URL`
    --include-all-branches,      # Include all branches from template repository
    --internal,                  # Make the new repository internal
    --license (-l): string,      # Specify an Open Source License for the repository
    --private,                   # Make the new repository private
    --public,                    # Make the new repository public
    --push,                      # Push local commits to the new repository
    --remote (-r): string,       # Specify remote name for the new repository
    --source (-s): string,       # Specify path to local repository to use as source
    --team (-t): string,         # The `name` of the organization team to be granted access
    --template (-p): string,     # Make the new repository based on a template `repository`
]: nothing -> string {
    ^gh repo create ...(nusage argv [$name] {
        --add-readme: $add_readme
        --clone: $clone
        --description: $description
        --disable-issues: $disable_issues
        --disable-wiki: $disable_wiki
        --gitignore: $gitignore
        --homepage: $homepage
        --include-all-branches: $include_all_branches
        --internal: $internal
        --license: $license
        --private: $private
        --public: $public
        --push: $push
        --remote: $remote
        --source: $source
        --team: $team
        --template: $template
    })
}

# Delete a repository
#
# Delete a GitHub repository.
#
# With no argument, deletes the current repository. Otherwise, deletes the specified repository.
#
# For safety, when no repository argument is provided, the `--yes` flag is ignored 
# and you will be prompted for confirmation. To delete the current repository non-interactively, 
# specify it explicitly (e.g., `gh repo delete owner/repo --yes`).
#
# Deletion requires authorization with the `delete_repo` scope.
# To authorize, run `gh auth refresh -s delete_repo`
@usage 'long_help "Delete a GitHub repository.\n\nWith no argument, deletes the current repository. Otherwise, deletes the specified repository.\n\nFor safety, when no repository argument is provided, the `--yes` flag is ignored \nand you will be prompted for confirmation. To delete the current repository non-interactively, \nspecify it explicitly (e.g., `gh repo delete owner/repo --yes`).\n\nDeletion requires authorization with the `delete_repo` scope.\nTo authorize, run `gh auth refresh -s delete_repo`\n"'
@usage 'flag --confirm help="Confirm deletion without prompting" hide=#true deprecated="use `--yes` instead"'
@usage 'flag --yes help="Confirm deletion without prompting"'
@usage 'arg "[repository]" required=#false'
export def "gh repo delete" [
    repository?: string,
    --yes,                # Confirm deletion without prompting
]: nothing -> string {
    ^gh repo delete ...(nusage argv [$repository] {--yes: $yes})
}

# Manage deploy keys in a repository
@usage 'flag "-R --repo" help="Select another repository using the `[HOST/]OWNER/REPO` format" global=#true {
            arg <REPO>
        }'
export def "gh repo deploy-key" [
    --repo (-R): string,  # Select another repository using the `[HOST/]OWNER/REPO` format
]: nothing -> string {
    ^gh repo deploy-key ...(nusage argv [] {--repo: $repo})
}

# Add a deploy key to a GitHub repository
#
# Note that any key added by gh will be associated with the current authentication token.
# If you de-authorize the GitHub CLI app or authentication token from your account, any
# deploy keys added by GitHub CLI will be removed as well.
@usage 'long_help "Add a deploy key to a GitHub repository.\n\nNote that any key added by gh will be associated with the current authentication token.\nIf you de-authorize the GitHub CLI app or authentication token from your account, any\ndeploy keys added by GitHub CLI will be removed as well.\n"'
@usage 'flag "-w --allow-write" help="Allow write access for the key"'
@usage 'flag "-t --title" help="Title of the new key" {
                arg <TITLE>
            }'
@usage 'arg <key-file>'
@usage 'example "# Generate a passwordless SSH key and add it as a deploy key to a repository\n$ ssh-keygen -t ed25519 -C \"my description\" -N \"\" -f ~/.ssh/gh-test\n$ gh repo deploy-key add ~/.ssh/gh-test.pub"'
export def "gh repo deploy-key add" [
    key_file: string,
    --repo (-R): string,   # Select another repository using the `[HOST/]OWNER/REPO` format
    --allow-write (-w),    # Allow write access for the key
    --title (-t): string,  # Title of the new key
]: nothing -> string {
    ^gh repo deploy-key add ...(nusage argv [$key_file] {--repo: $repo, --allow-write: $allow_write, --title: $title})
}

# Delete a deploy key from a GitHub repository
@usage 'arg <key-id>'
export def "gh repo deploy-key delete" [
    key_id: string,
    --repo (-R): string,  # Select another repository using the `[HOST/]OWNER/REPO` format
]: nothing -> string {
    ^gh repo deploy-key delete ...(nusage argv [$key_id] {--repo: $repo})
}

# List deploy keys in a GitHub repository
@usage 'alias ls'
@usage 'flag "-q --jq" help="Filter JSON output using a jq `expression`" {
                arg <JQ>
            }'
@usage 'flag --json help="Output JSON with the specified `fields`" {
                arg <JSON>
            }'
@usage 'flag "-t --template" help="Format JSON output using a Go template; see \"gh help formatting\"" {
                arg <TEMPLATE>
            }'
export def "gh repo deploy-key list" [
    --repo (-R): string,      # Select another repository using the `[HOST/]OWNER/REPO` format
    --jq (-q): string,        # Filter JSON output using a jq `expression`
    --json: string,           # Output JSON with the specified `fields`
    --template (-t): string,  # Format JSON output using a Go template; see "gh help formatting"
]: nothing -> string {
    ^gh repo deploy-key list ...(nusage argv [] {
        --repo: $repo
        --jq: $jq
        --json: $json
        --template: $template
    })
}

# Edit repository settings
#
# To toggle a setting off, use the `--<flag>=false` syntax.
#
# Changing repository visibility can have unexpected consequences including but not limited to:
#
# - Losing stars and watchers, affecting repository ranking
# - Detaching public forks from the network
# - Disabling push rulesets
# - Allowing access to GitHub Actions history and logs
#
# When the `--visibility` flag is used, `--accept-visibility-change-consequences` flag is required.
#
# For information on all the potential consequences, see <https://gh.io/setting-repository-visibility>.
#
# When the `--enable-squash-merge` flag is used, `--squash-merge-commit-message`
# can be used to change the default squash merge commit message behavior:
#
# - `default`: uses commit title and message for 1 commit, or pull request title and list of commits for 2 or more
# - `pr-title`: uses pull request title
# - `pr-title-commits`: uses pull request title and list of commits
# - `pr-title-description`: uses pull request title and description
@usage 'long_help "Edit repository settings.\n\nTo toggle a setting off, use the `--<flag>=false` syntax.\n\nChanging repository visibility can have unexpected consequences including but not limited to:\n\n- Losing stars and watchers, affecting repository ranking\n- Detaching public forks from the network\n- Disabling push rulesets\n- Allowing access to GitHub Actions history and logs\n\nWhen the `--visibility` flag is used, `--accept-visibility-change-consequences` flag is required.\n\nFor information on all the potential consequences, see <https://gh.io/setting-repository-visibility>.\n\nWhen the `--enable-squash-merge` flag is used, `--squash-merge-commit-message`\ncan be used to change the default squash merge commit message behavior:\n\n- `default`: uses commit title and message for 1 commit, or pull request title and list of commits for 2 or more\n- `pr-title`: uses pull request title\n- `pr-title-commits`: uses pull request title and list of commits\n- `pr-title-description`: uses pull request title and description\n"'
@usage 'flag --accept-visibility-change-consequences help="Accept the consequences of changing the repository visibility"'
@usage 'flag --add-topic help="Add repository topic" {
            arg <ADD_TOPIC>
        }'
@usage 'flag --allow-forking help="Allow forking of an organization repository"'
@usage 'flag --allow-update-branch help="Allow a pull request head branch that is behind its base branch to be updated"'
@usage 'flag --default-branch help="Set the default branch `name` for the repository" {
            arg <DEFAULT_BRANCH>
        }'
@usage 'flag --delete-branch-on-merge help="Delete head branch when pull requests are merged"'
@usage 'flag "-d --description" help="Description of the repository" {
            arg <DESCRIPTION>
        }'
@usage 'flag --enable-advanced-security help="Enable advanced security in the repository"'
@usage 'flag --enable-auto-merge help="Enable auto-merge functionality"'
@usage 'flag --enable-discussions help="Enable discussions in the repository"'
@usage 'flag --enable-issues help="Enable issues in the repository"'
@usage 'flag --enable-merge-commit help="Enable merging pull requests via merge commit"'
@usage 'flag --enable-projects help="Enable projects in the repository"'
@usage 'flag --enable-rebase-merge help="Enable merging pull requests via rebase"'
@usage 'flag --enable-secret-scanning help="Enable secret scanning in the repository"'
@usage 'flag --enable-secret-scanning-push-protection help="Enable secret scanning push protection in the repository. Secret scanning must be enabled first"'
@usage 'flag --enable-squash-merge help="Enable merging pull requests via squashed commit"'
@usage 'flag --enable-wiki help="Enable wiki in the repository"'
@usage 'flag "-h --homepage" help="Repository home page `URL`" {
            arg <HOMEPAGE>
        }'
@usage 'flag --remove-topic help="Remove repository topic" {
            arg <REMOVE_TOPIC>
        }'
@usage 'flag --squash-merge-commit-message help="The default value for a squash merge commit message: {default|pr-title|pr-title-commits|pr-title-description}" {
            arg <SQUASH_MERGE_COMMIT_MESSAGE>
        }'
@usage 'flag --template help="Make the repository available as a template repository"'
@usage 'flag --visibility help="Change the visibility of the repository to {public,private,internal}" {
            arg <VISIBILITY>
        }'
@usage 'arg "[repository]" required=#false'
@usage 'example "# Enable issues and wiki\n$ gh repo edit --enable-issues --enable-wiki\n\n# Disable projects\n$ gh repo edit --enable-projects=false"'
export def "gh repo edit" [
    repository?: string,
    --accept-visibility-change-consequences,   # Accept the consequences of changing the repository visibility
    --add-topic: string,                       # Add repository topic
    --allow-forking,                           # Allow forking of an organization repository
    --allow-update-branch,                     # Allow a pull request head branch that is behind its base branch to be updated
    --default-branch: string,                  # Set the default branch `name` for the repository
    --delete-branch-on-merge,                  # Delete head branch when pull requests are merged
    --description (-d): string,                # Description of the repository
    --enable-advanced-security,                # Enable advanced security in the repository
    --enable-auto-merge,                       # Enable auto-merge functionality
    --enable-discussions,                      # Enable discussions in the repository
    --enable-issues,                           # Enable issues in the repository
    --enable-merge-commit,                     # Enable merging pull requests via merge commit
    --enable-projects,                         # Enable projects in the repository
    --enable-rebase-merge,                     # Enable merging pull requests via rebase
    --enable-secret-scanning,                  # Enable secret scanning in the repository
    --enable-secret-scanning-push-protection,  # Enable secret scanning push protection in the repository. Secret scanning must be enabled first
    --enable-squash-merge,                     # Enable merging pull requests via squashed commit
    --enable-wiki,                             # Enable wiki in the repository
    --homepage (-h): string,                   # Repository home page `URL`
    --remove-topic: string,                    # Remove repository topic
    --squash-merge-commit-message: string,     # The default value for a squash merge commit message: {default|pr-title|pr-title-commits|pr-title-description}
    --template,                                # Make the repository available as a template repository
    --visibility: string,                      # Change the visibility of the repository to {public,private,internal}
]: nothing -> string {
    ^gh repo edit ...(nusage argv [$repository] {
        --accept-visibility-change-consequences: $accept_visibility_change_consequences
        --add-topic: $add_topic
        --allow-forking: $allow_forking
        --allow-update-branch: $allow_update_branch
        --default-branch: $default_branch
        --delete-branch-on-merge: $delete_branch_on_merge
        --description: $description
        --enable-advanced-security: $enable_advanced_security
        --enable-auto-merge: $enable_auto_merge
        --enable-discussions: $enable_discussions
        --enable-issues: $enable_issues
        --enable-merge-commit: $enable_merge_commit
        --enable-projects: $enable_projects
        --enable-rebase-merge: $enable_rebase_merge
        --enable-secret-scanning: $enable_secret_scanning
        --enable-secret-scanning-push-protection: $enable_secret_scanning_push_protection
        --enable-squash-merge: $enable_squash_merge
        --enable-wiki: $enable_wiki
        --homepage: $homepage
        --remove-topic: $remove_topic
        --squash-merge-commit-message: $squash_merge_commit_message
        --template: $template
        --visibility: $visibility
    })
}

# Create a fork of a repository
#
# With no argument, creates a fork of the current repository. Otherwise, forks
# the specified repository.
#
# By default, the new fork is set to be your `origin` remote and any existing
# origin remote is renamed to `upstream`. To alter this behavior, you can set
# a name for the new fork's remote with `--remote-name`.
#
# The `upstream` remote will be set as the default remote repository.
#
# Additional `git clone` flags can be passed after `--`.
@usage r#'long_help "Create a fork of a repository.\n\nWith no argument, creates a fork of the current repository. Otherwise, forks\nthe specified repository.\n\nBy default, the new fork is set to be your `origin` remote and any existing\norigin remote is renamed to `upstream`. To alter this behavior, you can set\na name for the new fork's remote with `--remote-name`.\n\nThe `upstream` remote will be set as the default remote repository.\n\nAdditional `git clone` flags can be passed after `--`.\n"'#
@usage 'flag --clone help="Clone the fork"'
@usage 'flag --default-branch-only help="Only include the default branch in the fork"'
@usage 'flag --fork-name help="Rename the forked repository" {
            arg <FORK_NAME>
        }'
@usage 'flag --org help="Create the fork in an organization" {
            arg <ORG>
        }'
@usage 'flag --remote help="Add a git remote for the fork"'
@usage 'flag --remote-name help="Specify the name for the new remote" default=origin {
            arg <REMOTE_NAME>
        }'
@usage 'arg "[repository]" required=#false'
@usage 'example "# Fork a repository\n$ gh repo fork owner/repo\n\n# Fork a repository and clone it locally\n$ gh repo fork owner/repo --clone\n\n# Fork a repository without cloning it, skip the prompt\n$ gh repo fork owner/repo --clone=false"'
export def "gh repo fork" [
    repository?: string,
    --clone,                # Clone the fork
    --default-branch-only,  # Only include the default branch in the fork
    --fork-name: string,    # Rename the forked repository
    --org: string,          # Create the fork in an organization
    --remote,               # Add a git remote for the fork
    --remote-name: string,  # Specify the name for the new remote
]: nothing -> string {
    ^gh repo fork ...(nusage argv [$repository] {
        --clone: $clone
        --default-branch-only: $default_branch_only
        --fork-name: $fork_name
        --org: $org
        --remote: $remote
        --remote-name: $remote_name
    })
}

# List and view available repository gitignore templates
export def "gh repo gitignore" []: nothing -> string {
    ^gh repo gitignore ...(nusage argv [] {})
}

# List available repository gitignore templates
@usage 'alias ls'
export def "gh repo gitignore list" []: nothing -> string {
    ^gh repo gitignore list ...(nusage argv [] {})
}

# View an available repository gitignore template
#
# View an available repository `.gitignore` template.
#
# `<template>` is a case-sensitive `.gitignore` template name.
#
# For a list of available templates, run `gh repo gitignore list`.
@usage 'long_help "View an available repository `.gitignore` template.\n\n`<template>` is a case-sensitive `.gitignore` template name.\n\nFor a list of available templates, run `gh repo gitignore list`.\n"'
@usage 'arg <template>'
@usage 'example "# View the Go gitignore template\n$ gh repo gitignore view Go\n\n# View the Python gitignore template\n$ gh repo gitignore view Python\n\n# Create a new .gitignore file using the Go template\n$ gh repo gitignore view Go > .gitignore\n\n# Create a new .gitignore file using the Python template\n$ gh repo gitignore view Python > .gitignore"'
export def "gh repo gitignore view" [
    template: string,
]: nothing -> string {
    ^gh repo gitignore view ...(nusage argv [$template] {})
}

# Explore repository licenses
export def "gh repo license" []: nothing -> string {
    ^gh repo license ...(nusage argv [] {})
}

# List common repository licenses
#
# For even more licenses, visit <https://choosealicense.com/appendix>
@usage 'alias ls'
@usage 'long_help "List common repository licenses.\n\nFor even more licenses, visit <https://choosealicense.com/appendix>\n"'
export def "gh repo license list" []: nothing -> string {
    ^gh repo license list ...(nusage argv [] {})
}

# View a specific repository license
#
# View a specific repository license by license key or SPDX ID.
#
# Run `gh repo license list` to see available commonly used licenses. For even more licenses, visit <https://choosealicense.com/appendix>.
@usage 'long_help "View a specific repository license by license key or SPDX ID.\n\nRun `gh repo license list` to see available commonly used licenses. For even more licenses, visit <https://choosealicense.com/appendix>.\n"'
@usage 'flag "-w --web" help="Open https://choosealicense.com/ in the browser"'
@usage 'arg <license-key-or-spdx-id>'
@usage 'example "# View the MIT license from SPDX ID\n$ gh repo license view MIT\n\n# View the MIT license from license key\n$ gh repo license view mit\n\n# View the GNU AGPL-3.0 license from SPDX ID\n$ gh repo license view AGPL-3.0\n\n# View the GNU AGPL-3.0 license from license key\n$ gh repo license view agpl-3.0\n\n# Create a LICENSE.md with the MIT license\n$ gh repo license view MIT > LICENSE.md"'
export def "gh repo license view" [
    license_key_or_spdx_id: string,
    --web (-w),                      # Open https://choosealicense.com/ in the browser
]: nothing -> string {
    ^gh repo license view ...(nusage argv [$license_key_or_spdx_id] {--web: $web})
}

# List repositories owned by user or organization
#
# List repositories owned by a user or organization.
#
# Note that the list will only include repositories owned by the provided argument,
# and the `--fork` or `--source` flags will not traverse ownership boundaries. For example,
# when listing the forks in an organization, the output would not include those owned by individual users.
@usage 'alias ls'
@usage 'long_help "List repositories owned by a user or organization.\n\nNote that the list will only include repositories owned by the provided argument,\nand the `--fork` or `--source` flags will not traverse ownership boundaries. For example,\nwhen listing the forks in an organization, the output would not include those owned by individual users.\n"'
@usage 'flag --archived help="Show only archived repositories"'
@usage 'flag --fork help="Show only forks"'
@usage 'flag "-q --jq" help="Filter JSON output using a jq `expression`" hide=#true {
            arg <JQ>
        }'
@usage 'flag --json help="Output JSON with the specified `fields`" {
            arg <JSON>
        }'
@usage 'flag "-l --language" help="Filter by primary coding language" {
            arg <LANGUAGE>
        }'
@usage 'flag "-L --limit" help="Maximum number of repositories to list" default="30" {
            arg <LIMIT>
        }'
@usage 'flag --no-archived help="Omit archived repositories"'
@usage 'flag --private help="Show only private repositories" hide=#true deprecated="use `--visibility=private` instead"'
@usage 'flag --public help="Show only public repositories" hide=#true deprecated="use `--visibility=public` instead"'
@usage 'flag --source help="Show only non-forks"'
@usage 'flag "-t --template" help="Format JSON output using a Go template; see \"gh help formatting\"" hide=#true {
            arg <TEMPLATE>
        }'
@usage 'flag --topic help="Filter by topic" {
            arg <TOPIC>
        }'
@usage 'flag --visibility help="Filter by repository visibility: {public|private|internal}" {
            arg <VISIBILITY>
        }'
@usage 'arg "[owner]" required=#false'
@usage 'output "json" framing="json" { schema "{\n  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",\n  \"title\": \"The repositories `gh repo list --json` selects, one array\",\n  \"type\": \"array\",\n  \"items\": {\"$ref\": \"#/$defs/repository\"},\n  \"$defs\": {\n    \"repository\": {\n      \"type\": \"object\",\n      \"required\": [\n        \"name\",\n        \"nameWithOwner\",\n        \"owner\",\n        \"description\",\n        \"url\",\n        \"isPrivate\",\n        \"isArchived\",\n        \"isFork\",\n        \"defaultBranchRef\",\n        \"stargazerCount\",\n        \"forkCount\",\n        \"createdAt\",\n        \"updatedAt\",\n        \"pushedAt\"\n      ],\n      \"additionalProperties\": false,\n      \"properties\": {\n        \"name\": {\"type\": \"string\"},\n        \"nameWithOwner\": {\"type\": \"string\"},\n        \"owner\": {\n          \"type\": \"object\",\n          \"required\": [\"id\", \"login\"],\n          \"additionalProperties\": false,\n          \"properties\": {\n            \"id\": {\"type\": \"string\"},\n            \"login\": {\"type\": \"string\"}\n          }\n        },\n        \"description\": {\"type\": \"string\"},\n        \"url\": {\"type\": \"string\"},\n        \"isPrivate\": {\"type\": \"boolean\"},\n        \"isArchived\": {\"type\": \"boolean\"},\n        \"isFork\": {\"type\": \"boolean\"},\n        \"defaultBranchRef\": {\n          \"type\": \"object\",\n          \"required\": [\"name\"],\n          \"additionalProperties\": false,\n          \"properties\": {\"name\": {\"type\": \"string\"}}\n        },\n        \"stargazerCount\": {\"type\": \"integer\"},\n        \"forkCount\": {\"type\": \"integer\"},\n        \"createdAt\": {\"type\": \"string\", \"format\": \"date-time\"},\n        \"updatedAt\": {\"type\": \"string\", \"format\": \"date-time\"},\n        \"pushedAt\": {\"anyOf\": [{\"type\": \"string\", \"format\": \"date-time\"}, {\"type\": \"null\"}]}\n      }\n    }\n  }\n}\n" }'
export def "gh repo list" [
    owner?: string,
    --archived,               # Show only archived repositories
    --fork,                   # Show only forks
    --language (-l): string,  # Filter by primary coding language
    --limit (-L): string,     # Maximum number of repositories to list
    --no-archived,            # Omit archived repositories
    --source,                 # Show only non-forks
    --topic: string,          # Filter by topic
    --visibility: string,     # Filter by repository visibility: {public|private|internal}
]: nothing -> table<name: string, nameWithOwner: string, owner: record<id: string, login: string>, description: string, url: string, isPrivate: bool, isArchived: bool, isFork: bool, defaultBranchRef: record<name: string>, stargazerCount: int, forkCount: int, createdAt: datetime, updatedAt: datetime, pushedAt: oneof<datetime, nothing>> {
    let text = ^gh repo list --json "name,nameWithOwner,owner,description,url,isPrivate,isArchived,isFork,defaultBranchRef,stargazerCount,forkCount,createdAt,updatedAt,pushedAt" ...(nusage argv [$owner] {
        --archived: $archived
        --fork: $fork
        --language: $language
        --limit: $limit
        --no-archived: $no_archived
        --source: $source
        --topic: $topic
        --visibility: $visibility
    })
    nusage decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"title\":\"The repositories `gh repo list --json` selects, one array\",\"type\":\"array\",\"items\":{\"$ref\":\"#/$defs/repository\"},\"$defs\":{\"repository\":{\"type\":\"object\",\"required\":[\"name\",\"nameWithOwner\",\"owner\",\"description\",\"url\",\"isPrivate\",\"isArchived\",\"isFork\",\"defaultBranchRef\",\"stargazerCount\",\"forkCount\",\"createdAt\",\"updatedAt\",\"pushedAt\"],\"additionalProperties\":false,\"properties\":{\"name\":{\"type\":\"string\"},\"nameWithOwner\":{\"type\":\"string\"},\"owner\":{\"type\":\"object\",\"required\":[\"id\",\"login\"],\"additionalProperties\":false,\"properties\":{\"id\":{\"type\":\"string\"},\"login\":{\"type\":\"string\"}}},\"description\":{\"type\":\"string\"},\"url\":{\"type\":\"string\"},\"isPrivate\":{\"type\":\"boolean\"},\"isArchived\":{\"type\":\"boolean\"},\"isFork\":{\"type\":\"boolean\"},\"defaultBranchRef\":{\"type\":\"object\",\"required\":[\"name\"],\"additionalProperties\":false,\"properties\":{\"name\":{\"type\":\"string\"}}},\"stargazerCount\":{\"type\":\"integer\"},\"forkCount\":{\"type\":\"integer\"},\"createdAt\":{\"type\":\"string\",\"format\":\"date-time\"},\"updatedAt\":{\"type\":\"string\",\"format\":\"date-time\"},\"pushedAt\":{\"anyOf\":[{\"type\":\"string\",\"format\":\"date-time\"},{\"type\":\"null\"}]}}}}}" { from json | into datetime createdAt | into datetime updatedAt | update pushedAt {|row| if $row.pushedAt == null { null } else { $row.pushedAt | into datetime } } }
}

# List a directory in a repository (preview)
#
# List the contents of a directory in a GitHub repository without cloning it.
#
# This command is in preview and subject to change without notice.
#
# By default, the directory is listed from the default branch. Use the `--ref` flag to
# list from a specific branch, tag, or commit. When no path is given, the repository root
# is listed.
@usage 'long_help "List the contents of a directory in a GitHub repository without cloning it.\n\nThis command is in preview and subject to change without notice.\n\nBy default, the directory is listed from the default branch. Use the `--ref` flag to\nlist from a specific branch, tag, or commit. When no path is given, the repository root\nis listed.\n"'
@usage 'flag "-R --repo" help="Select another repository using the `[HOST/]OWNER/REPO` format" global=#true {
            arg <REPO>
        }'
@usage 'flag "-q --jq" help="Filter JSON output using a jq `expression`" {
            arg <JQ>
        }'
@usage 'flag --json help="Output JSON with the specified `fields`" {
            arg <JSON>
        }'
@usage 'flag --ref help="The branch, tag, or commit to list from" {
            arg <REF>
        }'
@usage 'flag "-t --template" help="Format JSON output using a Go template; see \"gh help formatting\"" {
            arg <TEMPLATE>
        }'
@usage 'arg "[path]" required=#false'
@usage 'example "# List the root of the default branch\n$ gh repo read-dir --repo cli/cli\n\n# List a subdirectory\n$ gh repo read-dir docs --repo cli/cli\n\n# List a directory at a specific ref\n$ gh repo read-dir docs --repo cli/cli --ref v2.50.0\n\n# Print selected fields as JSON\n$ gh repo read-dir docs --repo cli/cli --json name,path,type,size"'
export def "gh repo read-dir" [
    path?: path,
    --repo (-R): string,      # Select another repository using the `[HOST/]OWNER/REPO` format
    --jq (-q): string,        # Filter JSON output using a jq `expression`
    --json: string,           # Output JSON with the specified `fields`
    --ref: string,            # The branch, tag, or commit to list from
    --template (-t): string,  # Format JSON output using a Go template; see "gh help formatting"
]: nothing -> string {
    ^gh repo read-dir ...(nusage argv [$path] {
        --repo: $repo
        --jq: $jq
        --json: $json
        --ref: $ref
        --template: $template
    })
}

# Read a file from a repository (preview)
#
# Read the contents of a file in a GitHub repository without cloning it.
#
# This command is in preview and subject to change without notice.
#
# By default, the file is read from the default branch. Use the `--ref` flag to
# read from a specific branch, tag, or commit.
#
# When run in TTY mode, the content is shown through your pager. When stdout is piped or
# redirected, the raw content is written directly. To save the file to disk instead, use
# the `--output` flag.
#
# By default, the command refuses to output a file that contains terminal escape sequences,
# since they could manipulate your terminal. Pass `--allow-escape-sequences` to read the file anyway.
# This check applies only to terminal and piped output; writing to disk with `--output` always
# includes the raw bytes, as if `--allow-escape-sequences` were given.
@usage 'long_help "Read the contents of a file in a GitHub repository without cloning it.\n\nThis command is in preview and subject to change without notice.\n\nBy default, the file is read from the default branch. Use the `--ref` flag to\nread from a specific branch, tag, or commit.\n\nWhen run in TTY mode, the content is shown through your pager. When stdout is piped or\nredirected, the raw content is written directly. To save the file to disk instead, use\nthe `--output` flag.\n\nBy default, the command refuses to output a file that contains terminal escape sequences,\nsince they could manipulate your terminal. Pass `--allow-escape-sequences` to read the file anyway.\nThis check applies only to terminal and piped output; writing to disk with `--output` always\nincludes the raw bytes, as if `--allow-escape-sequences` were given.\n"'
@usage 'flag "-R --repo" help="Select another repository using the `[HOST/]OWNER/REPO` format" global=#true {
            arg <REPO>
        }'
@usage 'flag --allow-escape-sequences help="Allow printing terminal escape sequences"'
@usage 'flag --clobber help="Overwrite the output path if it already exists"'
@usage 'flag "-q --jq" help="Filter JSON output using a jq `expression`" {
            arg <JQ>
        }'
@usage 'flag --json help="Output JSON with the specified `fields`" {
            arg <JSON>
        }'
@usage 'flag "-o --output" help="Write the file to a `path` instead of stdout" {
            arg <OUTPUT>
        }'
@usage 'flag --ref help="The branch, tag, or commit to read from" {
            arg <REF>
        }'
@usage 'flag "-t --template" help="Format JSON output using a Go template; see \"gh help formatting\"" {
            arg <TEMPLATE>
        }'
@usage 'arg <path>'
@usage 'example "# Read a file from the default branch\n$ gh repo read-file README.md --repo cli/cli\n\n# Read a file at a specific ref\n$ gh repo read-file README.md --repo cli/cli --ref v2.50.0\n\n# Save a file to disk\n$ gh repo read-file README.md --repo cli/cli --output download/README.md\n\n# Print selected fields as JSON\n$ gh repo read-file README.md --repo cli/cli --json name,path,size,type\n\n# Read a file that contains terminal escape sequences\n$ gh repo read-file path/to/file --repo OWNER/REPO --allow-escape-sequences"'
export def "gh repo read-file" [
    path: path,
    --repo (-R): string,       # Select another repository using the `[HOST/]OWNER/REPO` format
    --allow-escape-sequences,  # Allow printing terminal escape sequences
    --clobber,                 # Overwrite the output path if it already exists
    --jq (-q): string,         # Filter JSON output using a jq `expression`
    --json: string,            # Output JSON with the specified `fields`
    --output (-o): string,     # Write the file to a `path` instead of stdout
    --ref: string,             # The branch, tag, or commit to read from
    --template (-t): string,   # Format JSON output using a Go template; see "gh help formatting"
]: nothing -> string {
    ^gh repo read-file ...(nusage argv [$path] {
        --repo: $repo
        --allow-escape-sequences: $allow_escape_sequences
        --clobber: $clobber
        --jq: $jq
        --json: $json
        --output: $output
        --ref: $ref
        --template: $template
    })
}

# Rename a repository
#
# Rename a GitHub repository.
#
# `<new-name>` is the desired repository name without the owner.
#
# By default, the current repository is renamed. Otherwise, the repository specified
# with `--repo` is renamed.
#
# To transfer repository ownership to another user account or organization,
# you must follow additional steps on `github.com`.
#
# For more information on transferring repository ownership, see:
# <https://docs.github.com/en/repositories/creating-and-managing-repositories/transferring-a-repository>
@usage 'long_help "Rename a GitHub repository.\n\n`<new-name>` is the desired repository name without the owner.\n\nBy default, the current repository is renamed. Otherwise, the repository specified\nwith `--repo` is renamed.\n\nTo transfer repository ownership to another user account or organization,\nyou must follow additional steps on `github.com`.\n\nFor more information on transferring repository ownership, see:\n<https://docs.github.com/en/repositories/creating-and-managing-repositories/transferring-a-repository>\n"'
@usage 'flag "-R --repo" help="Select another repository using the `[HOST/]OWNER/REPO` format" global=#true {
            arg <REPO>
        }'
@usage 'flag --confirm help="Skip confirmation prompt" hide=#true deprecated="use `--yes` instead"'
@usage 'flag "-y --yes" help="Skip the confirmation prompt"'
@usage 'arg "[new-name]" required=#false'
@usage 'example "# Rename the current repository (foo/bar -> foo/baz)\n$ gh repo rename baz\n\n# Rename the specified repository (qux/quux -> qux/baz)\n$ gh repo rename -R qux/quux baz"'
export def "gh repo rename" [
    new_name?: string,
    --repo (-R): string,  # Select another repository using the `[HOST/]OWNER/REPO` format
    --yes (-y),           # Skip the confirmation prompt
]: nothing -> string {
    ^gh repo rename ...(nusage argv [$new_name] {--repo: $repo, --yes: $yes})
}

# Configure default repository for this directory
#
# This command sets the default remote repository to use when querying the
# GitHub API for the locally cloned repository.
#
# gh uses the default repository for things like:
#
#  - viewing and creating pull requests
#  - viewing and creating issues
#  - viewing and creating releases
#  - working with GitHub Actions
#
# ### NOTE: gh does not use the default repository for managing repository and environment secrets.
@usage 'long_help "This command sets the default remote repository to use when querying the\nGitHub API for the locally cloned repository.\n\ngh uses the default repository for things like:\n\n - viewing and creating pull requests\n - viewing and creating issues\n - viewing and creating releases\n - working with GitHub Actions\n\n### NOTE: gh does not use the default repository for managing repository and environment secrets."'
@usage 'flag "-u --unset" help="Unset the current default repository"'
@usage 'flag "-v --view" help="View the current default repository"'
@usage 'arg "[repository]" required=#false'
@usage 'example "# Interactively select a default repository\n$ gh repo set-default\n\n# Set a repository explicitly\n$ gh repo set-default owner/repo\n\n# Set a repository using a git remote name\n$ gh repo set-default origin\n\n# View the current default repository\n$ gh repo set-default --view\n\n# Show more repository options in the interactive picker\n$ git remote add newrepo https://github.com/owner/repo\n$ gh repo set-default"'
export def "gh repo set-default" [
    repository?: string,
    --unset (-u),         # Unset the current default repository
    --view (-v),          # View the current default repository
]: nothing -> string {
    ^gh repo set-default ...(nusage argv [$repository] {--unset: $unset, --view: $view})
}

# Sync a repository
#
# Sync destination repository from source repository. Syncing uses the default branch
# of the source repository to update the matching branch on the destination
# repository so they are equal. A fast forward update will be used except when the
# `--force` flag is specified, then the two branches will
# be synced using a hard reset.
#
# Without an argument, the local repository is selected as the destination repository.
#
# The source repository is the parent of the destination repository by default.
# This can be overridden with the `--source` flag.
@usage 'long_help "Sync destination repository from source repository. Syncing uses the default branch\nof the source repository to update the matching branch on the destination\nrepository so they are equal. A fast forward update will be used except when the\n`--force` flag is specified, then the two branches will\nbe synced using a hard reset.\n\nWithout an argument, the local repository is selected as the destination repository.\n\nThe source repository is the parent of the destination repository by default.\nThis can be overridden with the `--source` flag.\n"'
@usage 'flag "-b --branch" help="Branch to sync (default [default branch])" {
            arg <BRANCH>
        }'
@usage 'flag --force help="Hard reset the branch of the destination repository to match the source repository"'
@usage 'flag "-s --source" help="Source repository" {
            arg <SOURCE>
        }'
@usage 'arg "[destination-repository]" required=#false'
@usage 'example "# Sync local repository from remote parent\n$ gh repo sync\n\n# Sync local repository from remote parent on specific branch\n$ gh repo sync --branch v1\n\n# Sync remote fork from its parent\n$ gh repo sync owner/cli-fork\n\n# Sync remote repository from another remote repository\n$ gh repo sync owner/repo --source owner2/repo2"'
export def "gh repo sync" [
    destination_repository?: string,
    --branch (-b): string,            # Branch to sync (default [default branch])
    --force,                          # Hard reset the branch of the destination repository to match the source repository
    --source (-s): string,            # Source repository
]: nothing -> string {
    ^gh repo sync ...(nusage argv [$destination_repository] {--branch: $branch, --force: $force, --source: $source})
}

# Unarchive a repository
#
# Unarchive a GitHub repository.
#
# With no argument, unarchives the current repository.
@usage 'long_help "Unarchive a GitHub repository.\n\nWith no argument, unarchives the current repository."'
@usage 'flag --confirm help="Skip the confirmation prompt" hide=#true deprecated="use `--yes` instead"'
@usage 'flag "-y --yes" help="Skip the confirmation prompt"'
@usage 'arg "[repository]" required=#false'
export def "gh repo unarchive" [
    repository?: string,
    --yes (-y),           # Skip the confirmation prompt
]: nothing -> string {
    ^gh repo unarchive ...(nusage argv [$repository] {--yes: $yes})
}

# View a repository
#
# Display the description and the README of a GitHub repository.
#
# With no argument, the repository for the current directory is displayed.
#
# With `--web`, open the repository in a web browser instead.
#
# With `--branch`, view a specific branch of the repository.
@usage 'long_help "Display the description and the README of a GitHub repository.\n\nWith no argument, the repository for the current directory is displayed.\n\nWith `--web`, open the repository in a web browser instead.\n\nWith `--branch`, view a specific branch of the repository.\n"'
@usage 'flag "-b --branch" help="View a specific branch of the repository" {
            arg <BRANCH>
        }'
@usage 'flag "-q --jq" help="Filter JSON output using a jq `expression`" hide=#true {
            arg <JQ>
        }'
@usage 'flag --json help="Output JSON with the specified `fields`" {
            arg <JSON>
        }'
@usage 'flag "-t --template" help="Format JSON output using a Go template; see \"gh help formatting\"" hide=#true {
            arg <TEMPLATE>
        }'
@usage 'flag "-w --web" help="Open a repository in the browser" hide=#true'
@usage 'arg "[repository]" required=#false'
@usage 'output "json" framing="json" { schema "{\n  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",\n  \"title\": \"A repository, as `gh repo view --json` selects its fields\",\n  \"$ref\": \"#/$defs/repository\",\n  \"$defs\": {\n    \"repository\": {\n      \"type\": \"object\",\n      \"required\": [\n        \"name\",\n        \"nameWithOwner\",\n        \"owner\",\n        \"description\",\n        \"url\",\n        \"isPrivate\",\n        \"isArchived\",\n        \"isFork\",\n        \"defaultBranchRef\",\n        \"stargazerCount\",\n        \"forkCount\",\n        \"createdAt\",\n        \"updatedAt\",\n        \"pushedAt\"\n      ],\n      \"additionalProperties\": false,\n      \"properties\": {\n        \"name\": {\"type\": \"string\"},\n        \"nameWithOwner\": {\"type\": \"string\"},\n        \"owner\": {\n          \"type\": \"object\",\n          \"required\": [\"id\", \"login\"],\n          \"additionalProperties\": false,\n          \"properties\": {\n            \"id\": {\"type\": \"string\"},\n            \"login\": {\"type\": \"string\"}\n          }\n        },\n        \"description\": {\"type\": \"string\"},\n        \"url\": {\"type\": \"string\"},\n        \"isPrivate\": {\"type\": \"boolean\"},\n        \"isArchived\": {\"type\": \"boolean\"},\n        \"isFork\": {\"type\": \"boolean\"},\n        \"defaultBranchRef\": {\n          \"type\": \"object\",\n          \"required\": [\"name\"],\n          \"additionalProperties\": false,\n          \"properties\": {\"name\": {\"type\": \"string\"}}\n        },\n        \"stargazerCount\": {\"type\": \"integer\"},\n        \"forkCount\": {\"type\": \"integer\"},\n        \"createdAt\": {\"type\": \"string\", \"format\": \"date-time\"},\n        \"updatedAt\": {\"type\": \"string\", \"format\": \"date-time\"},\n        \"pushedAt\": {\"anyOf\": [{\"type\": \"string\", \"format\": \"date-time\"}, {\"type\": \"null\"}]}\n      }\n    }\n  }\n}\n" }'
export def "gh repo view" [
    repository?: string,
    --branch (-b): string,  # View a specific branch of the repository
]: nothing -> record<name: string, nameWithOwner: string, owner: record<id: string, login: string>, description: string, url: string, isPrivate: bool, isArchived: bool, isFork: bool, defaultBranchRef: record<name: string>, stargazerCount: int, forkCount: int, createdAt: datetime, updatedAt: datetime, pushedAt: oneof<datetime, nothing>> {
    let text = ^gh repo view --json "name,nameWithOwner,owner,description,url,isPrivate,isArchived,isFork,defaultBranchRef,stargazerCount,forkCount,createdAt,updatedAt,pushedAt" ...(nusage argv [$repository] {--branch: $branch})
    nusage decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"title\":\"A repository, as `gh repo view --json` selects its fields\",\"$ref\":\"#/$defs/repository\",\"$defs\":{\"repository\":{\"type\":\"object\",\"required\":[\"name\",\"nameWithOwner\",\"owner\",\"description\",\"url\",\"isPrivate\",\"isArchived\",\"isFork\",\"defaultBranchRef\",\"stargazerCount\",\"forkCount\",\"createdAt\",\"updatedAt\",\"pushedAt\"],\"additionalProperties\":false,\"properties\":{\"name\":{\"type\":\"string\"},\"nameWithOwner\":{\"type\":\"string\"},\"owner\":{\"type\":\"object\",\"required\":[\"id\",\"login\"],\"additionalProperties\":false,\"properties\":{\"id\":{\"type\":\"string\"},\"login\":{\"type\":\"string\"}}},\"description\":{\"type\":\"string\"},\"url\":{\"type\":\"string\"},\"isPrivate\":{\"type\":\"boolean\"},\"isArchived\":{\"type\":\"boolean\"},\"isFork\":{\"type\":\"boolean\"},\"defaultBranchRef\":{\"type\":\"object\",\"required\":[\"name\"],\"additionalProperties\":false,\"properties\":{\"name\":{\"type\":\"string\"}}},\"stargazerCount\":{\"type\":\"integer\"},\"forkCount\":{\"type\":\"integer\"},\"createdAt\":{\"type\":\"string\",\"format\":\"date-time\"},\"updatedAt\":{\"type\":\"string\",\"format\":\"date-time\"},\"pushedAt\":{\"anyOf\":[{\"type\":\"string\",\"format\":\"date-time\"},{\"type\":\"null\"}]}}}}}" { from json | into datetime createdAt | into datetime updatedAt | update pushedAt {|row| if $row.pushedAt == null { null } else { $row.pushedAt | into datetime } } }
}

# View details about workflow runs
#
# List, view, and watch recent workflow runs from GitHub Actions.
@usage 'long_help "List, view, and watch recent workflow runs from GitHub Actions."'
@usage 'flag "-R --repo" help="Select another repository using the `[HOST/]OWNER/REPO` format" global=#true {
        arg <REPO>
    }'
export def "gh run" [
    --repo (-R): string,  # Select another repository using the `[HOST/]OWNER/REPO` format
]: nothing -> string {
    ^gh run ...(nusage argv [] {--repo: $repo})
}

# Cancel a workflow run
@usage 'flag --force help="Force cancel a workflow run"'
@usage 'arg "[run-id]" required=#false'
export def "gh run cancel" [
    run_id?: string,
    --repo (-R): string,  # Select another repository using the `[HOST/]OWNER/REPO` format
    --force,              # Force cancel a workflow run
]: nothing -> string {
    ^gh run cancel ...(nusage argv [$run_id] {--repo: $repo, --force: $force})
}

# Delete a workflow run
@usage 'arg "[run-id]" required=#false'
@usage 'example "# Interactively select a run to delete\n$ gh run delete\n\n# Delete a specific run\n$ gh run delete 12345"'
export def "gh run delete" [
    run_id?: string,
    --repo (-R): string,  # Select another repository using the `[HOST/]OWNER/REPO` format
]: nothing -> string {
    ^gh run delete ...(nusage argv [$run_id] {--repo: $repo})
}

# Download artifacts generated by a workflow run
#
# Download artifacts generated by a GitHub Actions workflow run.
#
# The contents of each artifact will be extracted under separate directories based on
# the artifact name. If only a single artifact is specified, it will be extracted into
# the current directory.
#
# By default, this command downloads the latest artifact created and uploaded through
# GitHub Actions. Because workflows can delete or overwrite artifacts, `<run-id>`
# must be used to select an artifact from a specific workflow run.
@usage 'long_help "Download artifacts generated by a GitHub Actions workflow run.\n\nThe contents of each artifact will be extracted under separate directories based on\nthe artifact name. If only a single artifact is specified, it will be extracted into\nthe current directory.\n\nBy default, this command downloads the latest artifact created and uploaded through\nGitHub Actions. Because workflows can delete or overwrite artifacts, `<run-id>`\nmust be used to select an artifact from a specific workflow run.\n"'
@usage 'flag "-D --dir" help="The directory to download artifacts into" default="." {
            arg <DIR>
        }'
@usage 'flag "-n --name" help="Download artifacts that match any of the given names" {
            arg <NAME>
        }'
@usage 'flag "-p --pattern" help="Download artifacts that match a glob pattern" {
            arg <PATTERN>
        }'
@usage 'arg "[run-id]" required=#false'
@usage 'example "# Download all artifacts generated by a workflow run\n$ gh run download <run-id>\n\n# Download a specific artifact within a run\n$ gh run download <run-id> -n <name>\n\n# Download specific artifacts across all runs in a repository\n$ gh run download -n <name1> -n <name2>\n\n# Select artifacts to download interactively\n$ gh run download"'
export def "gh run download" [
    run_id?: string,
    --repo (-R): string,     # Select another repository using the `[HOST/]OWNER/REPO` format
    --dir (-D): string,      # The directory to download artifacts into
    --name (-n): string,     # Download artifacts that match any of the given names
    --pattern (-p): string,  # Download artifacts that match a glob pattern
]: nothing -> string {
    ^gh run download ...(nusage argv [$run_id] {
        --repo: $repo
        --dir: $dir
        --name: $name
        --pattern: $pattern
    })
}

# List recent workflow runs
#
# Note that providing the `workflow_name` to the `-w` flag will not fetch disabled workflows.
# Also pass the `-a` flag to fetch disabled workflow runs using the `workflow_name` and the `-w` flag.
#
# Runs created by organization and enterprise ruleset workflows will not display a workflow name due to GitHub API limitations.
#
# To see runs associated with a pull request, users should run `gh pr checks`.
@usage 'alias ls'
@usage 'long_help "List recent workflow runs.\n\nNote that providing the `workflow_name` to the `-w` flag will not fetch disabled workflows.\nAlso pass the `-a` flag to fetch disabled workflow runs using the `workflow_name` and the `-w` flag.\n\nRuns created by organization and enterprise ruleset workflows will not display a workflow name due to GitHub API limitations.\n\nTo see runs associated with a pull request, users should run `gh pr checks`.\n"'
@usage 'flag "-a --all" help="Include disabled workflows"'
@usage 'flag "-b --branch" help="Filter runs by branch" {
            arg <BRANCH>
        }'
@usage 'flag "-c --commit" help="Filter runs by the `SHA` of the commit" {
            arg <COMMIT>
        }'
@usage 'flag --created help="Filter runs by the `date` it was created" {
            arg <CREATED>
        }'
@usage 'flag "-e --event" help="Filter runs by which `event` triggered the run" {
            arg <EVENT>
        }'
@usage 'flag "-q --jq" help="Filter JSON output using a jq `expression`" hide=#true {
            arg <JQ>
        }'
@usage 'flag --json help="Output JSON with the specified `fields`" {
            arg <JSON>
        }'
@usage 'flag "-L --limit" help="Maximum number of runs to fetch" default="20" {
            arg <LIMIT>
        }'
@usage 'flag "-s --status" help="Filter runs by status: {queued|completed|in_progress|requested|waiting|pending|action_required|cancelled|failure|neutral|skipped|stale|startup_failure|success|timed_out}" {
            arg <STATUS>
        }'
@usage 'flag "-t --template" help="Format JSON output using a Go template; see \"gh help formatting\"" hide=#true {
            arg <TEMPLATE>
        }'
@usage 'flag "-u --user" help="Filter runs by user who triggered the run" {
            arg <USER>
        }'
@usage 'flag "-w --workflow" help="Filter runs by workflow" {
            arg <WORKFLOW>
        }'
@usage 'output "json" framing="json" { schema "{\n  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",\n  \"title\": \"The workflow runs `gh run list --json` selects, one array\",\n  \"type\": \"array\",\n  \"items\": {\"$ref\": \"#/$defs/run\"},\n  \"$defs\": {\n    \"run\": {\n      \"type\": \"object\",\n      \"required\": [\n        \"databaseId\",\n        \"number\",\n        \"attempt\",\n        \"name\",\n        \"displayTitle\",\n        \"workflowName\",\n        \"headBranch\",\n        \"headSha\",\n        \"event\",\n        \"status\",\n        \"conclusion\",\n        \"createdAt\",\n        \"updatedAt\",\n        \"startedAt\",\n        \"url\"\n      ],\n      \"additionalProperties\": false,\n      \"properties\": {\n        \"databaseId\": {\"type\": \"integer\"},\n        \"number\": {\"type\": \"integer\"},\n        \"attempt\": {\"type\": \"integer\"},\n        \"name\": {\"type\": \"string\"},\n        \"displayTitle\": {\"type\": \"string\"},\n        \"workflowName\": {\"type\": \"string\"},\n        \"headBranch\": {\"type\": \"string\"},\n        \"headSha\": {\"type\": \"string\"},\n        \"event\": {\"type\": \"string\"},\n        \"status\": {\"type\": \"string\"},\n        \"conclusion\": {\"type\": \"string\"},\n        \"createdAt\": {\"type\": \"string\", \"format\": \"date-time\"},\n        \"updatedAt\": {\"type\": \"string\", \"format\": \"date-time\"},\n        \"startedAt\": {\"type\": \"string\", \"format\": \"date-time\"},\n        \"url\": {\"type\": \"string\"}\n      }\n    }\n  }\n}\n" }'
export def "gh run list" [
    --repo (-R): string,      # Select another repository using the `[HOST/]OWNER/REPO` format
    --all (-a),               # Include disabled workflows
    --branch (-b): string,    # Filter runs by branch
    --commit (-c): string,    # Filter runs by the `SHA` of the commit
    --created: string,        # Filter runs by the `date` it was created
    --event (-e): string,     # Filter runs by which `event` triggered the run
    --limit (-L): string,     # Maximum number of runs to fetch
    --status (-s): string,    # Filter runs by status: {queued|completed|in_progress|requested|waiting|pending|action_required|cancelled|failure|neutral|skipped|stale|startup_failure|success|timed_out}
    --user (-u): string,      # Filter runs by user who triggered the run
    --workflow (-w): string,  # Filter runs by workflow
]: nothing -> table<databaseId: int, number: int, attempt: int, name: string, displayTitle: string, workflowName: string, headBranch: string, headSha: string, event: string, status: string, conclusion: string, createdAt: datetime, updatedAt: datetime, startedAt: datetime, url: string> {
    let text = ^gh run list --json "databaseId,number,attempt,name,displayTitle,workflowName,headBranch,headSha,event,status,conclusion,createdAt,updatedAt,startedAt,url" ...(nusage argv [] {
        --repo: $repo
        --all: $all
        --branch: $branch
        --commit: $commit
        --created: $created
        --event: $event
        --limit: $limit
        --status: $status
        --user: $user
        --workflow: $workflow
    })
    nusage decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"title\":\"The workflow runs `gh run list --json` selects, one array\",\"type\":\"array\",\"items\":{\"$ref\":\"#/$defs/run\"},\"$defs\":{\"run\":{\"type\":\"object\",\"required\":[\"databaseId\",\"number\",\"attempt\",\"name\",\"displayTitle\",\"workflowName\",\"headBranch\",\"headSha\",\"event\",\"status\",\"conclusion\",\"createdAt\",\"updatedAt\",\"startedAt\",\"url\"],\"additionalProperties\":false,\"properties\":{\"databaseId\":{\"type\":\"integer\"},\"number\":{\"type\":\"integer\"},\"attempt\":{\"type\":\"integer\"},\"name\":{\"type\":\"string\"},\"displayTitle\":{\"type\":\"string\"},\"workflowName\":{\"type\":\"string\"},\"headBranch\":{\"type\":\"string\"},\"headSha\":{\"type\":\"string\"},\"event\":{\"type\":\"string\"},\"status\":{\"type\":\"string\"},\"conclusion\":{\"type\":\"string\"},\"createdAt\":{\"type\":\"string\",\"format\":\"date-time\"},\"updatedAt\":{\"type\":\"string\",\"format\":\"date-time\"},\"startedAt\":{\"type\":\"string\",\"format\":\"date-time\"},\"url\":{\"type\":\"string\"}}}}}" { from json | into datetime createdAt | into datetime updatedAt | into datetime startedAt }
}

# Rerun a run
#
# Rerun an entire run, only failed jobs, or a specific job from a run.
#
# Note that due to historical reasons, the `--job` flag may not take what you expect.
# Specifically, when navigating to a job in the browser, the URL looks like this:
# `https://github.com/<owner>/<repo>/actions/runs/<run-id>/jobs/<number>`.
#
# However, this `<number>` should not be used with the `--job` flag and will result in the
# API returning `404 NOT FOUND`. Instead, you can get the correct job IDs using the following command:
#
# 	gh run view <run-id> --json jobs --jq '.jobs[] | {name, databaseId}'
#
# You will need to use databaseId field for triggering job re-runs.
@usage r#'long_help "Rerun an entire run, only failed jobs, or a specific job from a run.\n\nNote that due to historical reasons, the `--job` flag may not take what you expect.\nSpecifically, when navigating to a job in the browser, the URL looks like this:\n`https://github.com/<owner>/<repo>/actions/runs/<run-id>/jobs/<number>`.\n\nHowever, this `<number>` should not be used with the `--job` flag and will result in the\nAPI returning `404 NOT FOUND`. Instead, you can get the correct job IDs using the following command:\n\n\tgh run view <run-id> --json jobs --jq '.jobs[] | {name, databaseId}'\n\nYou will need to use databaseId field for triggering job re-runs.\n"'#
@usage 'flag "-d --debug" help="Rerun with debug logging"'
@usage 'flag --failed help="Rerun only failed jobs, including dependencies"'
@usage 'flag "-j --job" help="Rerun a specific job ID from a run, including dependencies" {
            arg <JOB>
        }'
@usage 'arg "[run-id]" required=#false'
export def "gh run rerun" [
    run_id?: string,
    --repo (-R): string,  # Select another repository using the `[HOST/]OWNER/REPO` format
    --debug (-d),         # Rerun with debug logging
    --failed,             # Rerun only failed jobs, including dependencies
    --job (-j): string,   # Rerun a specific job ID from a run, including dependencies
]: nothing -> string {
    ^gh run rerun ...(nusage argv [$run_id] {
        --repo: $repo
        --debug: $debug
        --failed: $failed
        --job: $job
    })
}

# View a summary of a workflow run
#
# Due to platform limitations, `gh` may not always be able to associate jobs with their
# corresponding logs when using the primary method of fetching logs in zip format.
#
# In such cases, `gh` will attempt to fetch logs for each job individually via the API.
# This fallback is slower and more resource-intensive. If more than 25 job logs are missing,
# the operation will fail with an error.
#
# Additionally, due to similar platform constraints, some log lines may not be
# associated with a specific step within a job. In these cases, the step name will
# appear as `UNKNOWN STEP` in the log output.
@usage 'long_help "View a summary of a workflow run.\n\nDue to platform limitations, `gh` may not always be able to associate jobs with their\ncorresponding logs when using the primary method of fetching logs in zip format.\n\nIn such cases, `gh` will attempt to fetch logs for each job individually via the API.\nThis fallback is slower and more resource-intensive. If more than 25 job logs are missing,\nthe operation will fail with an error.\n\nAdditionally, due to similar platform constraints, some log lines may not be\nassociated with a specific step within a job. In these cases, the step name will\nappear as `UNKNOWN STEP` in the log output.\n"'
@usage 'flag "-a --attempt" help="The attempt number of the workflow run" default="0" {
            arg <ATTEMPT>
        }'
@usage 'flag --exit-status help="Exit with non-zero status if run failed"'
@usage 'flag "-j --job" help="View a specific job ID from a run" {
            arg <JOB>
        }'
@usage 'flag "-q --jq" help="Filter JSON output using a jq `expression`" hide=#true {
            arg <JQ>
        }'
@usage 'flag --json help="Output JSON with the specified `fields`" {
            arg <JSON>
        }'
@usage 'flag --log help="View full log for either a run or specific job" hide=#true'
@usage 'flag --log-failed help="View the log for any failed steps in a run or specific job" hide=#true'
@usage 'flag "-t --template" help="Format JSON output using a Go template; see \"gh help formatting\"" hide=#true {
            arg <TEMPLATE>
        }'
@usage 'flag "-v --verbose" help="Show job steps"'
@usage 'flag "-w --web" help="Open run in the browser" hide=#true'
@usage 'arg "[run-id]" required=#false'
@usage 'example "# Interactively select a run to view, optionally selecting a single job\n$ gh run view\n\n# View a specific run\n$ gh run view 12345\n\n# View a specific run with specific attempt number\n$ gh run view 12345 --attempt 3\n\n# View a specific job within a run\n$ gh run view --job 456789\n\n# View the full log for a specific job\n$ gh run view --log --job 456789\n\n# Exit non-zero if a run failed\n$ gh run view 0451 --exit-status && echo \"run pending or passed\""'
@usage 'output "json" framing="json" { schema "{\n  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",\n  \"title\": \"A workflow run, as `gh run view --json` selects its fields\",\n  \"$ref\": \"#/$defs/run\",\n  \"$defs\": {\n    \"run\": {\n      \"type\": \"object\",\n      \"required\": [\n        \"databaseId\",\n        \"number\",\n        \"attempt\",\n        \"name\",\n        \"displayTitle\",\n        \"workflowName\",\n        \"headBranch\",\n        \"headSha\",\n        \"event\",\n        \"status\",\n        \"conclusion\",\n        \"createdAt\",\n        \"updatedAt\",\n        \"startedAt\",\n        \"url\"\n      ],\n      \"additionalProperties\": false,\n      \"properties\": {\n        \"databaseId\": {\"type\": \"integer\"},\n        \"number\": {\"type\": \"integer\"},\n        \"attempt\": {\"type\": \"integer\"},\n        \"name\": {\"type\": \"string\"},\n        \"displayTitle\": {\"type\": \"string\"},\n        \"workflowName\": {\"type\": \"string\"},\n        \"headBranch\": {\"type\": \"string\"},\n        \"headSha\": {\"type\": \"string\"},\n        \"event\": {\"type\": \"string\"},\n        \"status\": {\"type\": \"string\"},\n        \"conclusion\": {\"type\": \"string\"},\n        \"createdAt\": {\"type\": \"string\", \"format\": \"date-time\"},\n        \"updatedAt\": {\"type\": \"string\", \"format\": \"date-time\"},\n        \"startedAt\": {\"type\": \"string\", \"format\": \"date-time\"},\n        \"url\": {\"type\": \"string\"}\n      }\n    }\n  }\n}\n" }'
export def "gh run view" [
    run_id?: string,
    --repo (-R): string,     # Select another repository using the `[HOST/]OWNER/REPO` format
    --attempt (-a): string,  # The attempt number of the workflow run
    --exit-status,           # Exit with non-zero status if run failed
    --job (-j): string,      # View a specific job ID from a run
    --verbose (-v),          # Show job steps
]: nothing -> record<databaseId: int, number: int, attempt: int, name: string, displayTitle: string, workflowName: string, headBranch: string, headSha: string, event: string, status: string, conclusion: string, createdAt: datetime, updatedAt: datetime, startedAt: datetime, url: string> {
    let text = ^gh run view --json "databaseId,number,attempt,name,displayTitle,workflowName,headBranch,headSha,event,status,conclusion,createdAt,updatedAt,startedAt,url" ...(nusage argv [$run_id] {
        --repo: $repo
        --attempt: $attempt
        --exit-status: $exit_status
        --job: $job
        --verbose: $verbose
    })
    nusage decoded $text "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"title\":\"A workflow run, as `gh run view --json` selects its fields\",\"$ref\":\"#/$defs/run\",\"$defs\":{\"run\":{\"type\":\"object\",\"required\":[\"databaseId\",\"number\",\"attempt\",\"name\",\"displayTitle\",\"workflowName\",\"headBranch\",\"headSha\",\"event\",\"status\",\"conclusion\",\"createdAt\",\"updatedAt\",\"startedAt\",\"url\"],\"additionalProperties\":false,\"properties\":{\"databaseId\":{\"type\":\"integer\"},\"number\":{\"type\":\"integer\"},\"attempt\":{\"type\":\"integer\"},\"name\":{\"type\":\"string\"},\"displayTitle\":{\"type\":\"string\"},\"workflowName\":{\"type\":\"string\"},\"headBranch\":{\"type\":\"string\"},\"headSha\":{\"type\":\"string\"},\"event\":{\"type\":\"string\"},\"status\":{\"type\":\"string\"},\"conclusion\":{\"type\":\"string\"},\"createdAt\":{\"type\":\"string\",\"format\":\"date-time\"},\"updatedAt\":{\"type\":\"string\",\"format\":\"date-time\"},\"startedAt\":{\"type\":\"string\",\"format\":\"date-time\"},\"url\":{\"type\":\"string\"}}}}}" { from json | into datetime createdAt | into datetime updatedAt | into datetime startedAt }
}

# Watch a run until it completes, showing its progress
#
# By default, all steps are displayed. The `--compact` option can be used to only
# show the relevant/failed steps.
#
# This command does not support authenticating via fine grained PATs
# as it is not currently possible to create a PAT with the `checks:read` permission.
@usage 'long_help "Watch a run until it completes, showing its progress.\n\nBy default, all steps are displayed. The `--compact` option can be used to only\nshow the relevant/failed steps.\n\nThis command does not support authenticating via fine grained PATs\nas it is not currently possible to create a PAT with the `checks:read` permission.\n"'
@usage 'flag --compact help="Show only relevant/failed steps"'
@usage 'flag --exit-status help="Exit with non-zero status if run fails"'
@usage 'flag "-i --interval" help="Refresh interval in seconds" default="3" {
            arg <INTERVAL>
        }'
@usage 'arg <run-id>'
@usage r#'example "# Watch a run until it's done\n$ gh run watch\n\n# Watch a run in compact mode\n$ gh run watch --compact\n\n# Run some other command when the run is finished\n$ gh run watch && notify-send 'run is done!'"'#
export def "gh run watch" [
    run_id: string,
    --repo (-R): string,      # Select another repository using the `[HOST/]OWNER/REPO` format
    --compact,                # Show only relevant/failed steps
    --exit-status,            # Exit with non-zero status if run fails
    --interval (-i): string,  # Refresh interval in seconds
]: nothing -> string {
    ^gh run watch ...(nusage argv [$run_id] {
        --repo: $repo
        --compact: $compact
        --exit-status: $exit_status
        --interval: $interval
    })
}
