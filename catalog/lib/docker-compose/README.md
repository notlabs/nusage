# Docker Compose

Compose's command tree at v5.6.1, exported through usage's Cobra adapter, with typed `version`
and `ls`. `docker-compose.baseline.overlay.kdl` keeps the module to those two; the full spec is
committed, and the other commands stay with `^docker-compose`.

```nu
use docker-compose *

docker-compose version | get version
docker-compose ls | select Name Status ConfigFiles  # needs a Docker daemon
```

It calls the standalone `docker-compose` binary on PATH, which a Docker CLI plugin install does
not provide.
