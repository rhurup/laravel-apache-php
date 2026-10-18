# laravel-apache-php

Docker image for Laravel (and plain PHP) apps: **Apache 2.4 (mpm_event) + PHP-FPM + Composer + Node**, on Ubuntu 24.04 with PHP from the [ondrej/php PPA](https://launchpad.net/~ondrej/+archive/ubuntu/php).

- One Dockerfile for every PHP version: `8.3`, `8.4` and `8.5` are built and published, for `linux/amd64` and `linux/arm64`
- Everything runs as `www-data` (no root, no sudo), and supervisord is PID 1
- Optional Laravel workers (scheduler, Horizon, Reverb) are switched on and off with env vars
- Optionally clones or updates the app from git, writes `.env`, runs `composer install` and migrations at startup
- Has a healthcheck, rebuilds weekly to pick up security updates, and blocks dotfiles (`.env`, `.git`) and project files from being served

## Usage

```bash
docker run -d -p 8080:8080 -v "$PWD:/var/www" rhuruphansen/laravel-apache-php:8.4
```

Images are published to both [Docker Hub](https://hub.docker.com/r/rhuruphansen/laravel-apache-php) (`rhuruphansen/laravel-apache-php`) and GHCR (`ghcr.io/rhurup/laravel-apache-php`), with the same tags.

If `/var/www/artisan` exists, the docroot is `/var/www/public` (Laravel). If it doesn't, the docroot is `/var/www`. See [docker-compose.yml](docker-compose.yml) for a fuller example with Redis.

### Tags

| Tag | |
|---|---|
| `8.3`, `8.4`, `8.5` | Latest weekly build of that PHP version |
| `8.4-20261019` | Fixed build (date-stamped), for pinning in production |
| `latest` | Same as `8.4` |

### Build your own

```bash
docker build --build-arg PHP_VERSION=8.5 --build-arg USER_ID=$(id -u) --build-arg GROUP_ID=$(id -g) -t laravel-apache-php:8.5 .
```

| Build arg | Default | |
|---|---|---|
| `PHP_VERSION` | `8.4` | Any version in the ondrej PPA (8.3+ for the config syntax used) |
| `PHP_EXTENSIONS` | see Dockerfile | Package names without the `phpX.Y-` prefix. Packages that don't exist for that version are skipped |
| `USER_ID` / `GROUP_ID` | `1000` | UID/GID of `www-data`, set it to match the host user that owns the bind mount |
| `NODE_VERSION` | `22` | Copied from the official `node` image |

## Startup (entrypoint)

On every start, in order:

1. **SSH key**: if `~/.ssh/id_ed25519` or `~/.ssh/id_rsa` is mounted, it's added to ssh-agent (for private git repos)
2. **Git**: with `GIT_REPO_URI` + `GIT_REPO_BRANCH` set, an empty `/var/www` is cloned. An existing checkout is reset with `git fetch` + `git reset --hard origin/<branch>`, so local changes to tracked files are lost
3. **.env**: with `LARAVEL_ENV_ENABLED=true`, every `LARAVEL_*` env var is written to `/var/www/.env` with the prefix stripped (`LARAVEL_APP_KEY` becomes `APP_KEY`). The old file is kept once as `.env.old`. Only the key names are logged, never the values
4. **Composer**: `composer install` (from `composer.lock`, never `update`) when `composer.json` exists
5. **Migrations**: `php artisan migrate --force` when `artisan` exists
6. **Startup script**: runs `SHELL_STARTUP_SCRIPT` with bash if the file exists (relative to `/var/www`)
7. Starts supervisord: PHP-FPM, Apache and the enabled Laravel workers

If steps 2–6 fail, a warning is logged and startup continues.

## Environment variables

| Variable | Default | |
|---|---|---|
| `GIT_REPO_URI`, `GIT_REPO_BRANCH` | – | See Startup |
| `LARAVEL_ENV_ENABLED` | `false` | Write `LARAVEL_*` vars to `.env` |
| `COMPOSER_ENABLED` | `true` | Run `composer install` at startup |
| `LARAVEL_MIGRATION_ENABLED` | `true` | Run migrations at startup |
| `SHELL_STARTUP_SCRIPT` | – | Script to run before the services start |
| `LARAVEL_SCHEDULE_ENABLED` | `true` | `artisan schedule:work` |
| `LARAVEL_HORIZON_ENABLED` | `false` | `artisan horizon` |
| `LARAVEL_REVERB_ENABLED` | `false` | `artisan reverb:start` |
| `APACHE_PORT` | `8080` | Port Apache listens on inside the container |
| `APACHE_DOCUMENT_ROOT` | auto | Overrides the docroot detection |
| `APACHE_LIMIT_REQUEST_BODY` | `2147483647` | Max request body in bytes (0 = unlimited) |
| `PHP_MEMORY_LIMIT` | `512M` | |
| `PHP_UPLOAD_MAX_FILESIZE` / `PHP_POST_MAX_SIZE` | `2048M` / `2148M` | |
| `PHP_MAX_EXECUTION_TIME` / `PHP_MAX_INPUT_TIME` | `600` / `600` | |
| `PHP_MAX_FILE_UPLOADS` | `30` | |
| `PHP_TIMEZONE` | `Europe/Copenhagen` | |
| `PHP_OPCACHE_MEMORY` | `256` | MB |
| `PHP_OPCACHE_VALIDATE_TIMESTAMPS` | `1` | Set to `0` when code never changes inside a running container |
| `FPM_PM` | `dynamic` | `static`, `dynamic` or `ondemand` |
| `FPM_MAX_CHILDREN` | `100` | Size this to fit memory: children × memory per request should fit in RAM |
| `FPM_START_SERVERS` / `FPM_MIN_SPARE_SERVERS` / `FPM_MAX_SPARE_SERVERS` | `20` / `10` / `40` | |
| `FPM_MAX_REQUESTS` | `500` | |
| `FPM_REQUEST_TERMINATE_TIMEOUT` | `0` | Hard kill timeout per request |

## Notes

- **Port**: Apache listens on **8080**, not 80, because it doesn't run as root. Put a TLS-terminating reverse proxy (Traefik, Caddy, nginx) in front.
- **Shutdown**: Horizon gets up to an hour to finish its jobs, but Docker only waits 10 seconds by default. Set `stop_grace_period` to match.
- **Coverage**: pcov is installed but turned off. To use it: `php -d pcov.enabled=1 vendor/bin/phpunit --coverage-text`.
- **Node**: available on `PATH` as `node`, `npm`, `npx` and `corepack` (nvm is no longer used).

## License

[MIT](LICENSE)
