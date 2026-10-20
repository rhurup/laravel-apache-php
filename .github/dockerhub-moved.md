# ⚠️ Moved to rhuruphansen/laravel-apache-php

**This image is no longer updated.** Use [`rhuruphansen/laravel-apache-php`](https://hub.docker.com/r/rhuruphansen/laravel-apache-php) instead. It's a hardened rebuild with PHP 8.3, 8.4 and 8.5 and weekly security updates.

The new image has breaking changes, so check these before you switch:

- The container listens on **port 8080**, not 80. A mapping like `81:80` must become `81:8080`.
- Everything runs as `www-data`, and there is **no sudo**.
- The PHP-FPM socket is `/run/php/php-fpm.sock`. If you mount your own `www.conf`, update it to use that socket.
- Node is on `PATH` directly. **nvm isn't installed**, so scripts that run `source ~/.nvm/nvm.sh` must drop that line.

Source and documentation: [github.com/rhurup/laravel-apache-php](https://github.com/rhurup/laravel-apache-php)

This repository will be deleted once it's no longer in use.
