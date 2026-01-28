<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\KpiCalculatorService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Carbon\Carbon;

class AssetKpiController extends Controller
{
    public function __construct(
        private KpiCalculatorService $kpiService
    ) {}

    /**
     * Get all KPIs for a specific asset
     * 
     * GET /api/assets/{id}/kpis
     * Query params: start_date, end_date (optional)
     */
    public function index(Request $request, int $id): JsonResponse
    {
        $startDate = $request->has('start_date') 
            ? Carbon::parse($request->input('start_date')) 
            : null;
        
        $endDate = $request->has('end_date') 
            ? Carbon::parse($request->input('end_date')) 
            : null;

        $kpis = $this->kpiService->getAssetKpis($id, $startDate, $endDate);

        return response()->json([
            'success' => true,
            'data' => $kpis,
        ]);
    }

    /**
     * Get MTTR for a specific asset
     * 
     * GET /api/assets/{id}/mttr
     */
    public function mttr(int $id): JsonResponse
    {
        $mttr = $this->kpiService->getMttr($id);

        return response()->json([
            'success' => true,
            'data' => [
                'asset_id' => $id,
                'mttr_hours' => $mttr,
                'description' => 'Mean Time To Repair',
            ],
        ]);
    }

    /**
     * Get MTBF for a specific asset
     * 
     * GET /api/assets/{id}/mtbf
     */
    public function mtbf(int $id): JsonResponse
    {
        $mtbf = $this->kpiService->getMtbf($id);

        return response()->json([
            'success' => true,
            'data' => [
                'asset_id' => $id,
                'mtbf_hours' => $mtbf,
                'description' => 'Mean Time Between Failures',
            ],
        ]);
    }

    /**
     * Get Availability for a specific asset
     * 
     * GET /api/assets/{id}/availability
     */
    public function availability(int $id): JsonResponse
    {
        $availability = $this->kpiService->getAvailability($id);

        return response()->json([
            'success' => true,
            'data' => [
                'asset_id' => $id,
                'availability_percent' => $availability,
                'description' => 'Uptime / (Uptime + Downtime) × 100',
            ],
        ]);
    }

    /**
     * Get KPI trends over time
     * 
     * GET /api/assets/{id}/trends
     * Query params: period (default: 30), interval (default: week)
     */
    public function trends(Request $request, int $id): JsonResponse
    {
        $period = (int) $request->input('period', 30);
        $interval = $request->input('interval', 'week');

        $trends = $this->kpiService->getKpiTrends($id, $period, $interval);

        return response()->json([
            'success' => true,
            'data' => [
                'asset_id' => $id,
                'period_days' => $period,
                'interval' => $interval,
                'trends' => $trends,
            ],
        ]);
    }

    /**
     * Get OEE for a specific asset
     * 
     * GET /api/assets/{id}/oee
     * Query params: performance (default: 100), quality (default: 100)
     */
    public function oee(Request $request, int $id): JsonResponse
    {
        $performance = (float) $request->input('performance', 100);
        $quality = (float) $request->input('quality', 100);

        $oee = $this->kpiService->calculateOee($id, $performance, $quality);

        return response()->json([
            'success' => true,
            'data' => $oee,
        ]);
    }
}
