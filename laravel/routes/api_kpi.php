<?php

use Illuminate\Support\Facades\Route;
use App\Http\Controllers\Api\AssetKpiController;
use App\Http\Controllers\Api\DashboardController;

/*
|--------------------------------------------------------------------------
| KPI API Routes
|--------------------------------------------------------------------------
|
| These routes handle all KPI-related endpoints for the CMMS.
| All routes are prefixed with /api and protected by sanctum middleware.
|
*/

Route::middleware(['auth:sanctum'])->group(function () {
    
    // =======================================================================
    // Asset-specific KPI endpoints
    // =======================================================================
    
    Route::prefix('assets/{id}')->group(function () {
        // GET /api/assets/{id}/kpis - All KPIs for an asset
        Route::get('kpis', [AssetKpiController::class, 'index']);
        
        // GET /api/assets/{id}/mttr - Mean Time To Repair
        Route::get('mttr', [AssetKpiController::class, 'mttr']);
        
        // GET /api/assets/{id}/mtbf - Mean Time Between Failures
        Route::get('mtbf', [AssetKpiController::class, 'mtbf']);
        
        // GET /api/assets/{id}/availability - Availability percentage
        Route::get('availability', [AssetKpiController::class, 'availability']);
        
        // GET /api/assets/{id}/trends - KPI trends over time
        Route::get('trends', [AssetKpiController::class, 'trends']);
        
        // GET /api/assets/{id}/oee - Overall Equipment Effectiveness
        Route::get('oee', [AssetKpiController::class, 'oee']);
    });

    // =======================================================================
    // Fleet-wide KPI endpoints (Dashboard)
    // =======================================================================
    
    Route::prefix('kpis')->group(function () {
        // GET /api/kpis/summary - Fleet-wide KPI summary
        Route::get('summary', [DashboardController::class, 'summary']);
        
        // GET /api/kpis/all - All assets with KPIs (paginated)
        Route::get('all', [DashboardController::class, 'all']);
        
        // GET /api/kpis/critical - Assets in critical condition
        Route::get('critical', [DashboardController::class, 'critical']);
        
        // GET /api/kpis/top-performers - Best performing assets
        Route::get('top-performers', [DashboardController::class, 'topPerformers']);
        
        // GET /api/kpis/by-type - KPIs grouped by asset type
        Route::get('by-type', [DashboardController::class, 'byType']);
        
        // GET /api/kpis/attention-needed - Assets requiring attention
        Route::get('attention-needed', [DashboardController::class, 'attentionNeeded']);
    });
});

/*
|--------------------------------------------------------------------------
| API Endpoint Summary
|--------------------------------------------------------------------------
|
| Asset KPIs:
|   GET /api/assets/{id}/kpis?start_date=2024-01-01&end_date=2024-12-31
|   GET /api/assets/{id}/mttr
|   GET /api/assets/{id}/mtbf
|   GET /api/assets/{id}/availability
|   GET /api/assets/{id}/trends?period=30&interval=week
|   GET /api/assets/{id}/oee?performance=95&quality=98
|
| Dashboard:
|   GET /api/kpis/summary
|   GET /api/kpis/all?page=1&per_page=20
|   GET /api/kpis/critical
|   GET /api/kpis/top-performers?limit=10
|   GET /api/kpis/by-type
|   GET /api/kpis/attention-needed
|
*/
