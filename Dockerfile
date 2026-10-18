# syntax=docker/dockerfile:1.7
#
# Apache2 (mpm_event) + PHP-FPM + Composer + Node, built for Laravel.
# The PHP version is a build arg, so one Dockerfile builds every version:
#   docker build --build-arg PHP_VERSION=8.3 -t apache-php:8.3 .

ARG NODE_VERSION=22
ARG COMPOSER_VERSION=2

FROM composer:${COMPOSER_VERSION} AS composer
FROM node:${NODE_VERSION}-bookworm-slim AS node

FROM ubuntu:24.04

ARG PHP_VERSION=8.4
ARG USER_ID=1000
ARG GROUP_ID=1000
# Extensions without the "php<version>-" prefix. Packages that don't exist for
# the chosen PHP version (e.g. opcache, which is built in from 8.5) are skipped.
ARG PHP_EXTENSIONS="bcmath cli curl fpm gd imagick intl mbstring mcrypt mongodb mysql opcache pcov readline redis soap sqlite3 uuid xml xsl yaml zip"
ARG DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.title="apache-php" \
      org.opencontainers.image.description="Apache2 (mpm_event) + PHP-FPM + Composer + Node for Laravel" \
      org.opencontainers.image.authors="rasmus@huruphansen.dk"

ENV PHP_VERSION=${PHP_VERSION} \
    APACHE_PORT=8080 \
    COMPOSER_HOME=/home/www-data/.composer

# Keep /bin/sh -> bash, existing deploy scripts rely on bash-isms.
RUN ln -sf /bin/bash /bin/sh
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl gnupg software-properties-common \
 && add-apt-repository -y ppa:ondrej/php \
 && apt-get update \
 && apt-get upgrade -y \
 && pkgs=() \
 && for ext in ${PHP_EXTENSIONS}; do \
      if apt-cache show "php${PHP_VERSION}-${ext}" >/dev/null 2>&1; then pkgs+=("php${PHP_VERSION}-${ext}"); \
      else echo "WARNING: php${PHP_VERSION}-${ext} not available, skipping"; fi; \
    done \
 && apt-get install -y --no-install-recommends \
      apache2 git openssh-client unzip nano supervisor libfcgi-bin \
      mysql-client restic sshpass \
      "${pkgs[@]}" \
 && apt-get purge -y software-properties-common \
 && apt-get autoremove -y \
 && rm -rf /var/lib/apt/lists/*

COPY --from=composer /usr/bin/composer /usr/local/bin/composer
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
 && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
 && ln -s ../lib/node_modules/corepack/dist/corepack.js /usr/local/bin/corepack \
 && node --version && npm --version

# www-data gets the host UID/GID so bind mounts keep sane ownership.
RUN userdel -r ubuntu 2>/dev/null || true \
 && groupmod -g "${GROUP_ID}" www-data \
 && usermod -u "${USER_ID}" -g www-data -d /home/www-data -s /bin/bash www-data \
 && install -d -m 0755 -o www-data -g www-data \
      /home/www-data /var/www /disks /run/php /run/supervisor \
      /var/run/apache2 /var/lock/apache2 /var/log/apache2 \
 && install -d -m 0700 -o www-data -g www-data /home/www-data/.ssh \
 && rm -rf /var/www/html

# Apache: event MPM, no directory listing / status / CGI, minimal banner,
# unprivileged port so it can run as www-data.
RUN a2dismod -f mpm_prefork autoindex status cgi negotiation 2>/dev/null || true; \
    a2enmod mpm_event env headers proxy proxy_http proxy_fcgi rewrite setenvif \
 && a2disconf other-vhosts-access-log serve-cgi-bin \
 && sed -ri 's/^ServerTokens .*/ServerTokens Prod/; s/^ServerSignature .*/ServerSignature Off/; s/^TraceEnable .*/TraceEnable Off/' \
      /etc/apache2/conf-available/security.conf \
 && echo 'Listen ${APACHE_PORT}' > /etc/apache2/ports.conf \
 && echo 'ServerName localhost' > /etc/apache2/conf-available/servername.conf \
 && a2enconf servername \
 && ln -sf /dev/stdout /var/log/apache2/access.log \
 && ln -sf /dev/stderr /var/log/apache2/error.log

# PHP-FPM: run as www-data in the foreground, log to stderr.
RUN sed -ri \
      -e 's|^;?pid = .*|pid = /run/php/php-fpm.pid|' \
      -e 's|^;?error_log = .*|error_log = /proc/self/fd/2|' \
      /etc/php/${PHP_VERSION}/fpm/php-fpm.conf

COPY files/php-fpm-pool.conf /etc/php/${PHP_VERSION}/fpm/pool.d/www.conf
COPY files/php.ini /etc/php/${PHP_VERSION}/fpm/conf.d/99-docker.ini
COPY files/php.ini /etc/php/${PHP_VERSION}/cli/conf.d/99-docker.ini
COPY files/apache-vhost.conf /etc/apache2/sites-available/000-default.conf
COPY files/supervisord.conf /etc/supervisor/supervisord.conf
COPY files/supervisor/ /etc/supervisor/conf.d/
COPY --chmod=0755 files/bin/ /usr/local/bin/

USER www-data
WORKDIR /var/www

EXPOSE 8080

# Long start period: the entrypoint may run git, composer and migrations first.
HEALTHCHECK --interval=30s --timeout=5s --start-period=300s --retries=3 \
  CMD ["/usr/local/bin/healthcheck"]

ENTRYPOINT ["/usr/local/bin/docker-entrypoint"]
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
