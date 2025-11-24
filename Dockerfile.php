ARG PHP_VERSION=8.3
ARG COMPOSER_VERSION=2.8.1
ARG SITE_PATH=app/sites/demo

FROM ubuntu:24.04 AS php-base
ARG PHP_VERSION
ARG COMPOSER_VERSION
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        unzip \
        php${PHP_VERSION}-cli \
        php${PHP_VERSION}-fpm \
        php${PHP_VERSION}-bcmath \
        php${PHP_VERSION}-bz2 \
        php${PHP_VERSION}-curl \
        php${PHP_VERSION}-gd \
        php${PHP_VERSION}-intl \
        php${PHP_VERSION}-mbstring \
        php${PHP_VERSION}-mysql \
        php${PHP_VERSION}-opcache \
        php${PHP_VERSION}-readline \
        php${PHP_VERSION}-soap \
        php${PHP_VERSION}-sockets \
        php${PHP_VERSION}-xml \
        php${PHP_VERSION}-xsl \
        php${PHP_VERSION}-zip \
        php${PHP_VERSION}-redis \
    && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL https://getcomposer.org/installer -o /tmp/composer-setup.php \
    && php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer --version=${COMPOSER_VERSION} \
    && rm /tmp/composer-setup.php
COPY docker/php/www.conf /etc/php/${PHP_VERSION}/fpm/pool.d/www.conf
WORKDIR /var/www/html

FROM php-base AS runtime
EXPOSE 9000
CMD ["php-fpm8.3", "-F"]

FROM runtime AS release
ARG SITE_PATH
COPY ${SITE_PATH}/ /var/www/html/
RUN if [ -f composer.json ]; then composer install --no-dev --optimize-autoloader; fi
