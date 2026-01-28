# Render Build Script for Laravel
# This script runs during the build phase on Render

#!/usr/bin/env bash
set -e

echo "🚀 Starting Render build..."

# Install PHP dependencies
composer install --no-dev --optimize-autoloader

# Clear and cache config
php artisan config:cache
php artisan route:cache
php artisan view:cache

# Run migrations (optional - uncomment if needed)
# php artisan migrate --force

echo "✅ Build complete!"
