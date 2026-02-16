<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class BacklogController extends Controller
{
    /**
     * Full Work Order backlog with aging & urgency
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
        if ($request->has('urgency')) {
            $query->where('urgency_level', $request->input('urgency'));
        }
        if ($request->boolean('overdue_only')) {
            $query->where('is_overdue', true);
        }
        if ($request->has('asset_id')) {
            // Need to join back or filter — but view doesn't expose asset_id directly
            // We filter by asset name instead
            $query->where('asset_name', 'ILIKE', '%' . $request->input('asset_id') . '%');
        }

        $backlog = $query->get();

        return response()->json([
            'success' => true,
            'data' => $backlog,
            'meta' => [
                'total' => $backlog->count(),
                'overdue' => $backlog->where('is_overdue', true)->count(),
                'urgent' => $backlog->where('urgency_level', 'CRITICAL')->count(),
            ],
        ]);
    }

    /**
     * PM Backlog (overdue & unscheduled)
     * GET /api/backlog/pm
     */
    public function preventiveMaintenance(Request $request): JsonResponse
    {
        $query = DB::table('analytics.v_pm_backlog');

        if ($request->has('status')) {
            $query->where('backlog_status', $request->input('status'));
        }
        if ($request->has('criticality')) {
            $query->where('asset_criticality', $request->input('criticality'));
        }

        $backlog = $query->get();

        return response()->json([
            'success' => true,
            'data' => $backlog,
            'meta' => [
                'total' => $backlog->count(),
                'critical_overdue' => $backlog->where('backlog_status', 'CRITICAL_OVERDUE')->count(),
                'overdue' => $backlog->where('backlog_status', 'OVERDUE')->count(),
                'unscheduled' => $backlog->where('backlog_status', 'UNSCHEDULED')->count(),
            ],
        ]);
    }

    /**
     * Dashboard summary (single-row totals)
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
     * Backlog grouped by priority
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
     * Backlog grouped by asset
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
     * Backlog aging buckets
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
     * Backlog trend over time (opened vs closed per day)
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

        // Calculate running total
        $runningTotal = 0;
        $trend = array_map(function ($row) use (&$runningTotal) {
            $runningTotal += $row->net_change;
            $row->cumulative_backlog = $runningTotal;
            return $row;
        }, $data);

        return response()->json([
            'success' => true,
            'data' => $trend,
            'meta' => [
                'start_date' => $start,
                'end_date' => $end,
                'total_opened' => collect($data)->sum('opened_count'),
                'total_closed' => collect($data)->sum('closed_count'),
                'net_change' => collect($data)->sum('net_change'),
            ],
        ]);
    }
}
