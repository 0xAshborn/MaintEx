<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\SupabaseService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Alternative KPI Controller using Supabase REST API
 * 
 * Use this if you prefer Supabase's REST API over direct PostgreSQL
 * Benefits: Works with Supabase RLS, easier frontend integration
 */
class SupabaseKpiController extends Controller
{
    public function __construct(
        private SupabaseService $supabase
    ) {}

    /**
     * Get all KPIs for an asset via Supabase RPC
     * 
     * GET /api/supabase/assets/{id}/kpis
     */
    public function assetKpis(Request $request, int $id): JsonResponse
    {
        $startDate = $request->input('start_date');
        $endDate = $request->input('end_date');

        $kpis = $this->supabase->getAssetKpis($id, $startDate, $endDate);

        return response()->json([
            'success' => true,
            'source' => 'supabase_rpc',
            'data' => $kpis,
        ]);
    }

    /**
     * Get Asset 360 view via Supabase REST
     * 
     * GET /api/supabase/assets/{id}/360
     */
    public function asset360(int $id): JsonResponse
    {
        $data = $this->supabase->getAsset360($id);

        if (!$data) {
            return response()->json([
                'success' => false,
                'error' => 'Asset not found',
            ], 404);
        }

        return response()->json([
            'success' => true,
            'source' => 'supabase_view',
            'data' => $data,
        ]);
    }

    /**
     * Get KPI Dashboard via Supabase REST
     * 
     * GET /api/supabase/kpis/dashboard
     */
    public function dashboard(Request $request): JsonResponse
    {
        $filters = [];
        
        // Example filters
        if ($request->has('health_status')) {
            $filters['kpi_health_status'] = "eq.{$request->input('health_status')}";
        }
        
        if ($request->has('asset_type')) {
            $filters['asset_type'] = "eq.{$request->input('asset_type')}";
        }

        // Pagination
        if ($request->has('limit')) {
            $filters['limit'] = $request->input('limit');
        }
        
        if ($request->has('offset')) {
            $filters['offset'] = $request->input('offset');
        }

        $data = $this->supabase->getKpiDashboard($filters);

        return response()->json([
            'success' => true,
            'source' => 'supabase_view',
            'data' => $data,
            'count' => count($data),
        ]);
    }

    /**
     * Get realtime subscription config for frontend
     * 
     * GET /api/supabase/realtime/config
     */
    public function realtimeConfig(Request $request): JsonResponse
    {
        $table = $request->input('table', 'assets_downtime_events');
        $event = $request->input('event', '*');

        $config = $this->supabase->getRealtimeConfig($table, $event);

        return response()->json([
            'success' => true,
            'data' => $config,
        ]);
    }

    /**
     * Direct query to any view (for flexibility)
     * 
     * GET /api/supabase/views/{view}
     */
    public function queryView(Request $request, string $view): JsonResponse
    {
        // Whitelist allowed views for security
        $allowedViews = [
            'analytics_v_kpi_dashboard',
            'analytics_v_asset_360',
            'analytics_v_asset_mttr',
            'analytics_v_asset_mtbf',
            'analytics_v_asset_availability',
            'analytics_v_asset_reliability',
        ];

        if (!in_array($view, $allowedViews)) {
            return response()->json([
                'success' => false,
                'error' => 'View not allowed',
            ], 403);
        }

        $filters = $request->except(['_token']);
        $data = $this->supabase->query($view, $filters);

        return response()->json([
            'success' => true,
            'view' => $view,
            'data' => $data,
        ]);
    }
}
