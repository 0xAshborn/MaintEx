#!/usr/bin/env bash
# ====================================================================================
# CORTEX — Render Build Script
# Runs during the Docker BUILD phase.
# NOTE: Do NOT run config:cache here — Render env vars are injected at runtime only.
# ====================================================================================
set -e

echo "🔨 Starting CORTEX build..."

# Install PHP dependencies (production, optimized autoloader)
composer install --no-dev --optimize-autoloader

# Only cache views (path-based, env-independent)
php artisan view:cache

echo "✅ Build complete! Env-dependent caching deferred to startup.sh"
