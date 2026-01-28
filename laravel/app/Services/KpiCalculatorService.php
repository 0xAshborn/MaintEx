<?php

namespace App\Services;

use Illuminate\Support\Facades\DB;
use Carbon\Carbon;

/**
 * Service for calculating maintenance KPIs
 * 
 * Metrics calculated:
 * - MTTR: Mean Time To Repair
 * - MTBF: Mean Time Between Failures
 * - MTTF: Mean Time To Failure
 * - Availability: Uptime percentage
 * - Reliability: Probability of no failure
 * - Utilization: Actual vs planned runtime
 */
class KpiCalculatorService
{
    /**
     * Get all KPIs for a specific asset
     */
    public function getAssetKpis(int $assetId, ?Carbon $startDate = null, ?Carbon $endDate = null): array
    {
        // Use PostgreSQL function for date-range queries
        if ($startDate || $endDate) {
            return $this->getAssetKpisForPeriod($assetId, $startDate, $endDate);
        }

        // Use the master dashboard view for lifetime KPIs
        $kpi = DB::table('analytics.v_kpi_dashboard')
            ->where('asset_id', $assetId)
            ->first();

        if (!$kpi) {
            return $this->emptyKpiResponse($assetId);
        }

        return [
            'asset_id' => $kpi->asset_id,
            'asset_name' => $kpi->asset_name,
            'tag_number' => $kpi->tag_number,
            'asset_type' => $kpi->asset_type,
            'kpis' => [
                'availability' => [
                    'value' => (float) $kpi->availability_percent,
                    'unit' => '%',
                    'description' => 'Uptime / (Uptime + Downtime)'
                ],
                'reliability_30day' => [
                    'value' => (float) $kpi->reliability_30day_percent,
                    'unit' => '%',
                    'description' => 'Probability of no failure in next 30 days'
                ],
                'reliability_7day' => [
                    'value' => (float) $kpi->reliability_7day_percent,
                    'unit' => '%',
                    'description' => 'Probability of no failure in next 7 days'
                ],
                'utilization' => [
                    'value' => (float) ($kpi->utilization_percent ?? 0),
                    'unit' => '%',
                    'description' => 'Actual Runtime / Planned Runtime'
                ],
                'mttr' => [
                    'value' => (float) $kpi->mttr_hours,
                    'unit' => 'hours',
                    'description' => 'Mean Time To Repair'
                ],
                'mtbf' => [
                    'value' => $kpi->mtbf_hours ? (float) $kpi->mtbf_hours : null,
                    'unit' => 'hours',
                    'description' => 'Mean Time Between Failures'
                ],
                'mttf' => [
                    'value' => $kpi->mttf_hours ? (float) $kpi->mttf_hours : null,
                    'unit' => 'hours',
                    'description' => 'Mean Time To Failure (first failure)'
                ],
            ],
            'failure_count' => (int) $kpi->failure_count,
            'health_status' => $kpi->kpi_health_status,
        ];
    }

    /**
     * Get KPIs for a specific date range using PostgreSQL function
     */
    private function getAssetKpisForPeriod(int $assetId, ?Carbon $startDate, ?Carbon $endDate): array
    {
        $result = DB::selectOne(
            "SELECT * FROM analytics.get_asset_kpis(?, ?, ?)",
            [$assetId, $startDate?->toDateString(), $endDate?->toDateString()]
        );

        if (!$result) {
            return $this->emptyKpiResponse($assetId);
        }

        return [
            'asset_id' => $result->asset_id,
            'asset_name' => $result->asset_name,
            'period' => [
                'start' => $result->period_start,
                'end' => $result->period_end,
            ],
            'kpis' => [
                'availability' => [
                    'value' => (float) $result->availability_percent,
                    'unit' => '%',
                ],
                'mttr' => [
                    'value' => (float) $result->mttr_hours,
                    'unit' => 'hours',
                ],
                'mtbf' => [
                    'value' => $result->mtbf_hours ? (float) $result->mtbf_hours : null,
                    'unit' => 'hours',
                ],
            ],
            'failure_count' => (int) $result->failure_count,
        ];
    }

    /**
     * Get MTTR for an asset
     */
    public function getMttr(int $assetId): ?float
    {
        $result = DB::table('analytics.v_asset_mttr')
            ->where('asset_id', $assetId)
            ->value('mttr_hours');

        return $result ? (float) $result : null;
    }

    /**
     * Get MTBF for an asset
     */
    public function getMtbf(int $assetId): ?float
    {
        $result = DB::table('analytics.v_asset_mtbf')
            ->where('asset_id', $assetId)
            ->value('mtbf_hours');

        return $result ? (float) $result : null;
    }

    /**
     * Get Availability for an asset
     */
    public function getAvailability(int $assetId): ?float
    {
        $result = DB::table('analytics.v_asset_availability')
            ->where('asset_id', $assetId)
            ->value('availability_percent');

        return $result ? (float) $result : null;
    }

    /**
     * Get fleet-wide KPI summary
     */
    public function getFleetSummary(): array
    {
        $stats = DB::table('analytics.v_kpi_dashboard')
            ->selectRaw("
                COUNT(*) as total_assets,
                AVG(availability_percent) as avg_availability,
                AVG(reliability_30day_percent) as avg_reliability,
                AVG(mttr_hours) as avg_mttr,
                AVG(mtbf_hours) as avg_mtbf,
                SUM(failure_count) as total_failures,
                COUNT(*) FILTER (WHERE kpi_health_status = 'CRITICAL') as critical_count,
                COUNT(*) FILTER (WHERE kpi_health_status = 'WARNING') as warning_count,
                COUNT(*) FILTER (WHERE kpi_health_status = 'HEALTHY') as healthy_count
            ")
            ->first();

        return [
            'total_assets' => (int) $stats->total_assets,
            'averages' => [
                'availability' => round((float) $stats->avg_availability, 2),
                'reliability_30day' => round((float) $stats->avg_reliability, 2),
                'mttr_hours' => round((float) $stats->avg_mttr, 2),
                'mtbf_hours' => $stats->avg_mtbf ? round((float) $stats->avg_mtbf, 2) : null,
            ],
            'total_failures' => (int) $stats->total_failures,
            'health_distribution' => [
                'critical' => (int) $stats->critical_count,
                'warning' => (int) $stats->warning_count,
                'healthy' => (int) $stats->healthy_count,
            ],
        ];
    }

    /**
     * Get KPI trends over time
     */
    public function getKpiTrends(int $assetId, int $periodDays = 30, string $interval = 'week'): array
    {
        $endDate = Carbon::now();
        $startDate = $endDate->copy()->subDays($periodDays);

        // Get downtime events grouped by interval
        $trends = DB::table('assets.downtime_events')
            ->where('asset_id', $assetId)
            ->whereBetween('started_at', [$startDate, $endDate])
            ->selectRaw("
                DATE_TRUNC(?, started_at) as period,
                COUNT(*) FILTER (WHERE reason = 'Breakdown') as failures,
                SUM(duration_hours) as downtime_hours
            ", [$interval])
            ->groupByRaw("DATE_TRUNC(?, started_at)", [$interval])
            ->orderBy('period')
            ->get();

        return $trends->map(function ($row) {
            return [
                'period' => $row->period,
                'failures' => (int) $row->failures,
                'downtime_hours' => round((float) $row->downtime_hours, 2),
            ];
        })->toArray();
    }

    /**
     * Calculate OEE (Overall Equipment Effectiveness)
     * OEE = Availability × Performance × Quality
     */
    public function calculateOee(int $assetId, float $performanceRate = 100, float $qualityRate = 100): array
    {
        $availability = $this->getAvailability($assetId) ?? 100;

        $oee = ($availability / 100) * ($performanceRate / 100) * ($qualityRate / 100) * 100;

        return [
            'asset_id' => $assetId,
            'availability' => round($availability, 2),
            'performance' => round($performanceRate, 2),
            'quality' => round($qualityRate, 2),
            'oee' => round($oee, 2),
            'oee_class' => $this->getOeeClass($oee),
        ];
    }

    /**
     * Get OEE classification
     */
    private function getOeeClass(float $oee): string
    {
        return match (true) {
            $oee >= 85 => 'World Class',
            $oee >= 75 => 'Good',
            $oee >= 65 => 'Average',
            $oee >= 50 => 'Below Average',
            default => 'Poor',
        };
    }

    /**
     * Empty response when asset not found
     */
    private function emptyKpiResponse(int $assetId): array
    {
        return [
            'asset_id' => $assetId,
            'error' => 'Asset not found or no data available',
            'kpis' => null,
        ];
    }
}
