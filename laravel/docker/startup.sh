#!/usr/bin/env bash
# ====================================================================================
# CORTEX — Docker Entrypoint / Startup Script
# Runs at CONTAINER START (not build time), so env vars are available.
# ====================================================================================
set -e

echo "🚀 Starting CORTEX API..."

# Clear any stale cached config/routes that were baked into the image
# (Render env vars are only injected at runtime, not build time)
php artisan config:clear  2>/dev/null || true
php artisan route:clear   2>/dev/null || true
php artisan view:clear    2>/dev/null || true

# Re-cache with live env vars
php artisan config:cache
php artisan route:cache
php artisan view:cache

echo "✅ Cache warmed. Handing off to supervisord..."

# Start supervisord (nginx + php-fpm)
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
