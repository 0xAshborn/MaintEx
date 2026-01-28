<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\KpiCalculatorService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class DashboardController extends Controller
{
    public function __construct(
        private KpiCalculatorService $kpiService
    ) {}

    /**
     * Get fleet-wide KPI summary
     * 
     * GET /api/kpis/summary
     */
    public function summary(): JsonResponse
    {
        $summary = $this->kpiService->getFleetSummary();

        return response()->json([
            'success' => true,
            'data' => $summary,
        ]);
    }

    /**
     * Get all assets with their KPIs (paginated)
     * 
     * GET /api/kpis/all
     * Query params: page, per_page (default: 20)
     */
    public function all(Request $request): JsonResponse
    {
        $perPage = (int) $request->input('per_page', 20);

        $assets = DB::table('analytics.v_kpi_dashboard')
            ->paginate($perPage);

        return response()->json([
            'success' => true,
            'data' => $assets->items(),
            'meta' => [
                'current_page' => $assets->currentPage(),
                'per_page' => $assets->perPage(),
                'total' => $assets->total(),
                'last_page' => $assets->lastPage(),
            ],
        ]);
    }

    /**
     * Get critical assets (low availability or high failure rate)
     * 
     * GET /api/kpis/critical
     */
    public function critical(): JsonResponse
    {
        $criticalAssets = DB::table('analytics.v_kpi_dashboard')
            ->whereIn('kpi_health_status', ['CRITICAL', 'WARNING'])
            ->orderByRaw("
                CASE kpi_health_status 
                    WHEN 'CRITICAL' THEN 1 
                    WHEN 'WARNING' THEN 2 
                    ELSE 3 
                END
            ")
            ->limit(50)
            ->get();

        return response()->json([
            'success' => true,
            'data' => $criticalAssets,
            'count' => $criticalAssets->count(),
        ]);
    }

    /**
     * Get top performers (highest availability)
     * 
     * GET /api/kpis/top-performers
     */
    public function topPerformers(Request $request): JsonResponse
    {
        $limit = (int) $request->input('limit', 10);

        $topAssets = DB::table('analytics.v_kpi_dashboard')
            ->orderByDesc('availability_percent')
            ->limit($limit)
            ->get();

        return response()->json([
            'success' => true,
            'data' => $topAssets,
        ]);
    }

    /**
     * Get KPIs grouped by asset type
     * 
     * GET /api/kpis/by-type
     */
    public function byType(): JsonResponse
    {
        $byType = DB::table('analytics.v_kpi_dashboard')
            ->selectRaw("
                asset_type,
                COUNT(*) as asset_count,
                ROUND(AVG(availability_percent), 2) as avg_availability,
                ROUND(AVG(mttr_hours), 2) as avg_mttr,
                ROUND(AVG(mtbf_hours), 2) as avg_mtbf,
                SUM(failure_count) as total_failures
            ")
            ->groupBy('asset_type')
            ->orderByDesc('asset_count')
            ->get();

        return response()->json([
            'success' => true,
            'data' => $byType,
        ]);
    }

    /**
     * Get assets needing attention (upcoming PMs, overdue, etc.)
     * 
     * GET /api/kpis/attention-needed
     */
    public function attentionNeeded(): JsonResponse
    {
        $attention = DB::table('analytics.v_asset_360')
            ->whereIn('health_score', ['CRITICAL', 'OVERDUE', 'ATTENTION'])
            ->select([
                'asset_id',
                'asset_name',
                'tag_number',
                'status',
                'health_score',
                'open_tickets_count',
                'next_pm_date',
            ])
            ->orderByRaw("
                CASE health_score 
                    WHEN 'CRITICAL' THEN 1 
                    WHEN 'OVERDUE' THEN 2 
                    WHEN 'ATTENTION' THEN 3 
                END
            ")
            ->limit(50)
            ->get();

        return response()->json([
            'success' => true,
            'data' => $attention,
            'count' => $attention->count(),
        ]);
    }
}
