<?php

use Illuminate\Support\Facades\Route;
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\AssetController;
use App\Http\Controllers\Api\AssetKpiController;
use App\Http\Controllers\Api\WorkOrderController;
use App\Http\Controllers\Api\DashboardController;
use App\Http\Controllers\Api\CalendarController;
use App\Http\Controllers\Api\BacklogController;

/*
|--------------------------------------------------------------------------
| CORTEX API Routes
|--------------------------------------------------------------------------
|
| Full-stack Laravel API for CMMS connected to Supabase PostgreSQL
|
*/

// =======================================================================
// Public Routes (No Authentication)
// =======================================================================

Route::prefix('auth')->group(function () {
    Route::post('login', [AuthController::class, 'login']);
    Route::post('register', [AuthController::class, 'register']);
});

// Health check for Render
Route::get('health', fn() => response()->json(['status' => 'ok', 'timestamp' => now()]));

// =======================================================================
// Protected Routes (Require Authentication)
// =======================================================================

Route::middleware('auth:sanctum')->group(function () {

    // ===================================================================
    // Auth
    // ===================================================================
    Route::prefix('auth')->group(function () {
        Route::post('logout', [AuthController::class, 'logout']);
        Route::get('me', [AuthController::class, 'me']);
        Route::post('refresh', [AuthController::class, 'refresh']);
    });

    // ===================================================================
    // Assets CRUD
    // ===================================================================
    Route::apiResource('assets', AssetController::class);
    
    // Asset Actions
    Route::prefix('assets/{id}')->group(function () {
        // Downtime recording
        Route::post('downtime', [AssetController::class, 'recordDowntime']);
        Route::put('downtime/{eventId}/end', [AssetController::class, 'endDowntime']);
        
        // KPIs
        Route::get('kpis', [AssetKpiController::class, 'index']);
        Route::get('mttr', [AssetKpiController::class, 'mttr']);
        Route::get('mtbf', [AssetKpiController::class, 'mtbf']);
        Route::get('availability', [AssetKpiController::class, 'availability']);
        Route::get('trends', [AssetKpiController::class, 'trends']);
        Route::get('oee', [AssetKpiController::class, 'oee']);
    });

    // ===================================================================
    // Work Orders CRUD
    // ===================================================================
    Route::apiResource('work-orders', WorkOrderController::class);
    
    // Work Order Actions
    Route::prefix('work-orders/{id}')->group(function () {
        Route::post('start', [WorkOrderController::class, 'start']);
        Route::post('complete', [WorkOrderController::class, 'complete']);
    });

    // ===================================================================
    // KPI Dashboard
    // ===================================================================
    Route::prefix('kpis')->group(function () {
        Route::get('summary', [DashboardController::class, 'summary']);
        Route::get('all', [DashboardController::class, 'all']);
        Route::get('critical', [DashboardController::class, 'critical']);
        Route::get('top-performers', [DashboardController::class, 'topPerformers']);
        Route::get('by-type', [DashboardController::class, 'byType']);
        Route::get('attention-needed', [DashboardController::class, 'attentionNeeded']);
    });

    // ===================================================================
    // Calendar (PM Scheduling with Drag-and-Drop)
    // ===================================================================
    Route::prefix('calendar')->group(function () {
        Route::get('events', [CalendarController::class, 'events']);
        Route::get('pm', [CalendarController::class, 'pmSchedules']);
        Route::put('pm/{id}/reschedule', [CalendarController::class, 'reschedule']);
        Route::put('pm/batch-reschedule', [CalendarController::class, 'batchReschedule']);
        Route::get('pm/unscheduled', [CalendarController::class, 'unscheduled']);
        Route::get('pm/overdue', [CalendarController::class, 'overdue']);
    });

    // ===================================================================
    // Backlog (Aging, Trends, Urgency Analysis)
    // ===================================================================
    Route::prefix('backlog')->group(function () {
        Route::get('summary', [BacklogController::class, 'summary']);
        Route::get('work-orders', [BacklogController::class, 'workOrders']);
        Route::get('pm', [BacklogController::class, 'preventiveMaintenance']);
        Route::get('by-priority', [BacklogController::class, 'byPriority']);
        Route::get('by-asset', [BacklogController::class, 'byAsset']);
        Route::get('aging', [BacklogController::class, 'aging']);
        Route::get('trend', [BacklogController::class, 'trend']);
    });

});
