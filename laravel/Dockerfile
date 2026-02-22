# ====================================================================================
# CORTEX Laravel API - Dockerfile for Render
# ====================================================================================

FROM php:8.2-fpm

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    libpng-dev \
    libonig-dev \
    libxml2-dev \
    libpq-dev \
    zip \
    unzip \
    nginx \
    supervisor

# Clear cache
RUN apt-get clean && rm -rf /var/lib/apt/lists/*

# Install PHP extensions
RUN docker-php-ext-install pdo pdo_pgsql pgsql mbstring exif pcntl bcmath gd

# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Set working directory
WORKDIR /var/www/html

# Copy application files
# Handle both Vulcan root context (Railway) and laravel/ context
COPY . /tmp/src
RUN if [ -d "/tmp/src/laravel" ]; then \
    cp -a /tmp/src/laravel/. /var/www/html/; \
    else \
    cp -a /tmp/src/. /var/www/html/; \
    fi \
    && rm -rf /tmp/src

# Create required directories BEFORE composer install
RUN mkdir -p /var/www/html/bootstrap/cache \
    && mkdir -p /var/www/html/storage/logs \
    && mkdir -p /var/www/html/storage/framework/cache \
    && mkdir -p /var/www/html/storage/framework/sessions \
    && mkdir -p /var/www/html/storage/framework/views \
    && chmod -R 777 /var/www/html/bootstrap/cache \
    && chmod -R 777 /var/www/html/storage

# Install dependencies
RUN composer install --no-dev --optimize-autoloader --no-scripts

# Run post-install scripts manually
RUN php artisan package:discover --ansi || true

# Set final permissions
RUN chown -R www-data:www-data /var/www/html \
    && chmod -R 755 /var/www/html/storage \
    && chmod -R 755 /var/www/html/bootstrap/cache

# Create nginx config inline
RUN echo 'server {' > /etc/nginx/sites-available/default && \
    echo '    listen 80;' >> /etc/nginx/sites-available/default && \
    echo '    server_name _;' >> /etc/nginx/sites-available/default && \
    echo '    root /var/www/html/public;' >> /etc/nginx/sites-available/default && \
    echo '    index index.php;' >> /etc/nginx/sites-available/default && \
    echo '    add_header X-Frame-Options "SAMEORIGIN";' >> /etc/nginx/sites-available/default && \
    echo '    add_header X-Content-Type-Options "nosniff";' >> /etc/nginx/sites-available/default && \
    echo '    add_header X-XSS-Protection "1; mode=block";' >> /etc/nginx/sites-available/default && \
    echo '    gzip on;' >> /etc/nginx/sites-available/default && \
    echo '    gzip_types text/plain application/json application/javascript text/css;' >> /etc/nginx/sites-available/default && \
    echo '    location / { try_files $uri $uri/ /index.php?$query_string; }' >> /etc/nginx/sites-available/default && \
    echo '    location ~ \.php$ {' >> /etc/nginx/sites-available/default && \
    echo '        fastcgi_pass 127.0.0.1:9000;' >> /etc/nginx/sites-available/default && \
    echo '        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;' >> /etc/nginx/sites-available/default && \
    echo '        include fastcgi_params;' >> /etc/nginx/sites-available/default && \
    echo '        fastcgi_hide_header X-Powered-By;' >> /etc/nginx/sites-available/default && \
    echo '    }' >> /etc/nginx/sites-available/default && \
    echo '    location ~ /\.(?!well-known).* { deny all; }' >> /etc/nginx/sites-available/default && \
    echo '    location /api/health {' >> /etc/nginx/sites-available/default && \
    echo '        access_log off;' >> /etc/nginx/sites-available/default && \
    echo '        try_files $uri $uri/ /index.php?$query_string;' >> /etc/nginx/sites-available/default && \
    echo '    }' >> /etc/nginx/sites-available/default && \
    echo '}' >> /etc/nginx/sites-available/default

# Create supervisor config inline
RUN echo '[supervisord]' > /etc/supervisor/conf.d/supervisord.conf && \
    echo 'nodaemon=true' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo 'user=root' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo 'logfile=/var/log/supervisor/supervisord.log' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo 'pidfile=/var/run/supervisord.pid' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo '[program:php-fpm]' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo 'command=/usr/local/sbin/php-fpm -F' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo 'autostart=true' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo 'autorestart=true' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo 'stdout_logfile=/dev/stdout' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo 'stdout_logfile_maxbytes=0' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo 'stderr_logfile=/dev/stderr' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo 'stderr_logfile_maxbytes=0' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo '[program:nginx]' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo 'command=/usr/sbin/nginx -g "daemon off;"' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo 'autostart=true' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo 'autorestart=true' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo 'stdout_logfile=/dev/stdout' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo 'stdout_logfile_maxbytes=0' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo 'stderr_logfile=/dev/stderr' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo 'stderr_logfile_maxbytes=0' >> /etc/supervisor/conf.d/supervisord.conf

# Create startup script directly in the image to avoid missing file errors
RUN echo '#!/usr/bin/env bash' > /startup.sh && \
    echo 'echo "Starting CORTEX API..."' >> /startup.sh && \
    echo 'php artisan optimize:clear 2>/dev/null || true' >> /startup.sh && \
    echo 'exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf' >> /startup.sh && \
    chmod +x /startup.sh

# Expose port
EXPOSE 80

# startup.sh: clears stale caches, re-caches with live env vars, then starts supervisord
CMD ["/startup.sh"]
