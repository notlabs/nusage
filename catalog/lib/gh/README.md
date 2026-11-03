# GitHub CLI

gh's command tree, exported through usage's Cobra adapter. The commands `schemas/outputs.nuon`
types are in the module, with the fields it selects; the overlays say what else they hide and
why, and the rest stays with `^gh`. It calls the `gh` on PATH, with the user's own
authentication.

```nu
use gh *

gh pr list --repo notlabs/nusage --state all | select number title state author.login
```

The checks read this repository on GitHub, so they need `GH_TOKEN` or `GITHUB_TOKEN`.
