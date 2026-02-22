#!/usr/bin/env bash
# ====================================================================================
# CORTEX — Docker Entrypoint / Startup Script
# Runs at CONTAINER START (not build time), so env vars are available.
# NOTE: Do NOT use set -e here — artisan failures must not abort supervisord startup.
# ====================================================================================

echo "🚀 Starting CORTEX API..."

# ── 1. Clear any stale caches from the Docker image ──────────────────────────────────
echo "📦 Clearing stale caches..."
php artisan config:clear  2>/dev/null || echo "  config:clear skipped"
php artisan route:clear   2>/dev/null || echo "  route:clear skipped"
php artisan view:clear    2>/dev/null || echo "  view:clear skipped"

# ── 2. Re-cache for production ────────────────────────────────────────────────────────
echo "⚡ Re-caching with live env vars..."
php artisan config:cache  && echo "  ✅ config:cache OK"  || echo "  ⚠️  config:cache FAILED — running uncached"
php artisan route:cache   && echo "  ✅ route:cache OK"   || echo "  ⚠️  route:cache FAILED — running uncached"
php artisan view:cache    && echo "  ✅ view:cache OK"    || echo "  ⚠️  view:cache FAILED — running uncached"

# ── 3. Always start supervisord (nginx + php-fpm) ────────────────────────────────────
echo "✅ Handing off to supervisord..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
