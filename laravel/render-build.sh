#!/usr/bin/env bash
# ====================================================================================
# CORTEX — Render Build Script
# Runs during the Docker BUILD phase on Render
# ====================================================================================
set -e

echo "🚀 Starting CORTEX Render build..."

# Install PHP dependencies (production only, optimized autoloader)
composer install --no-dev --optimize-autoloader

# Clear any stale caches from previous builds
php artisan config:clear
php artisan route:clear
php artisan view:clear

# Re-cache for production performance
php artisan config:cache
php artisan route:cache
php artisan view:cache

echo "✅ Build complete!"
