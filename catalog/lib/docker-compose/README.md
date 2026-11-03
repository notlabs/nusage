# Docker Compose

Compose's command tree, exported through usage's Cobra adapter; the commands whose outputs
`docker-compose.outputs.overlay.kdl` declares are typed, and the others are hidden by
`docker-compose.baseline.overlay.kdl` and stay with `^docker-compose`. The full spec is
committed.

```nu
use docker-compose *

docker-compose version | get version
```

It calls the standalone `docker-compose` binary on PATH, which a Docker CLI plugin install does
not provide. Compose's project options are root flags it reads while traversing to a
subcommand, not flags each subcommand inherits, so the module's subcommands take none of them:
run from the project's directory, or use `^docker-compose` for those options.
