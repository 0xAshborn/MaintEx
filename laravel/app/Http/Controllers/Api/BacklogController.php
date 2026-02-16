<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class BacklogController extends Controller
{
    /**
     * Work Order Backlog — all open/pending WOs with aging & urgency
     * GET /api/backlog/work-orders
     */
    public function workOrders(Request $request): JsonResponse
    {
        $query = DB::table('analytics.v_wo_backlog');

        // Filters
        if ($request->has('priority')) {
            $query->where('priority', $request->input('priority'));
        }
        if ($request->has('status')) {
            $query->where('status', $request->input('status'));
        }
        if ($request->has('urgency_level')) {
            $query->where('urgency_level', $request->input('urgency_level'));
        }
        if ($request->boolean('overdue_only')) {
            $query->where('is_overdue', true);
        }
        if ($request->has('asset_name')) {
            $query->where('asset_name', 'ILIKE', '%' . $request->input('asset_name') . '%');
        }

        $backlog = $query->get();

        return response()->json([
            'success' => true,
            'data' => $backlog,
            'meta' => [
                'total' => $backlog->count(),
                'overdue' => $backlog->where('is_overdue', true)->count(),
            ],
        ]);
    }

    /**
     * PM Backlog — overdue & unscheduled preventive maintenance
     * GET /api/backlog/pm
     */
    public function pmBacklog(Request $request): JsonResponse
    {
        $query = DB::table('analytics.v_pm_backlog');

        if ($request->has('backlog_status')) {
            $query->where('backlog_status', $request->input('backlog_status'));
        }
        if ($request->has('asset_criticality')) {
            $query->where('asset_criticality', $request->input('asset_criticality'));
        }

        $backlog = $query->get();

        return response()->json([
            'success' => true,
            'data' => $backlog,
            'meta' => [
                'total' => $backlog->count(),
            ],
        ]);
    }

    /**
     * Backlog Summary — single-row dashboard KPIs
     * GET /api/backlog/summary
     */
    public function summary(): JsonResponse
    {
        $summary = DB::table('analytics.v_backlog_summary')->first();

        return response()->json([
            'success' => true,
            'data' => $summary,
        ]);
    }

    /**
     * Backlog by Priority — for charts
     * GET /api/backlog/by-priority
     */
    public function byPriority(): JsonResponse
    {
        $data = DB::table('analytics.v_backlog_by_priority')->get();

        return response()->json([
            'success' => true,
            'data' => $data,
        ]);
    }

    /**
     * Backlog by Asset — which assets have the most pending work
     * GET /api/backlog/by-asset
     */
    public function byAsset(): JsonResponse
    {
        $data = DB::table('analytics.v_backlog_by_asset')->get();

        return response()->json([
            'success' => true,
            'data' => $data,
        ]);
    }

    /**
     * Backlog Aging — age distribution in time buckets
     * GET /api/backlog/aging
     */
    public function aging(): JsonResponse
    {
        $data = DB::table('analytics.v_backlog_aging')->get();

        return response()->json([
            'success' => true,
            'data' => $data,
        ]);
    }

    /**
     * Backlog Trend — daily opened vs closed WOs
     * GET /api/backlog/trend?start=2026-01-01&end=2026-02-16
     */
    public function trend(Request $request): JsonResponse
    {
        $start = $request->input('start', now()->subDays(30)->toDateString());
        $end = $request->input('end', now()->toDateString());

        $data = DB::select(
            'SELECT * FROM analytics.get_backlog_trend(?, ?)',
            [$start, $end]
        );

        return response()->json([
            'success' => true,
            'data' => $data,
            'meta' => [
                'start' => $start,
                'end' => $end,
            ],
        ]);
    }
}
