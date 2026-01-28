<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * API Resource for Asset KPI responses
 * 
 * Transforms raw database data into consistent API format
 */
class AssetKpiResource extends JsonResource
{
    /**
     * Transform the resource into an array.
     */
    public function toArray(Request $request): array
    {
        return [
            'asset' => [
                'id' => $this->asset_id,
                'name' => $this->asset_name,
                'tag_number' => $this->tag_number,
                'type' => $this->asset_type,
            ],
            'kpis' => [
                'availability' => $this->formatKpi(
                    $this->availability_percent,
                    '%',
                    'Percentage of time asset is operational'
                ),
                'reliability' => [
                    '7_day' => $this->formatKpi(
                        $this->reliability_7day_percent,
                        '%',
                        'Probability of no failure in next 7 days'
                    ),
                    '30_day' => $this->formatKpi(
                        $this->reliability_30day_percent,
                        '%',
                        'Probability of no failure in next 30 days'
                    ),
                ],
                'utilization' => $this->formatKpi(
                    $this->utilization_percent,
                    '%',
                    'Actual runtime vs planned runtime'
                ),
                'mttr' => $this->formatKpi(
                    $this->mttr_hours,
                    'hours',
                    'Mean Time To Repair'
                ),
                'mtbf' => $this->formatKpi(
                    $this->mtbf_hours,
                    'hours',
                    'Mean Time Between Failures'
                ),
                'mttf' => $this->formatKpi(
                    $this->mttf_hours,
                    'hours',
                    'Mean Time To Failure'
                ),
            ],
            'health' => [
                'status' => $this->kpi_health_status,
                'status_color' => $this->getStatusColor($this->kpi_health_status),
                'failure_count' => (int) $this->failure_count,
            ],
            'meta' => [
                'calculated_at' => now()->toIso8601String(),
            ],
        ];
    }

    /**
     * Format a KPI value with metadata
     */
    private function formatKpi($value, string $unit, string $description): array
    {
        return [
            'value' => $value !== null ? round((float) $value, 2) : null,
            'unit' => $unit,
            'description' => $description,
        ];
    }

    /**
     * Get color code for health status
     */
    private function getStatusColor(string $status): string
    {
        return match ($status) {
            'CRITICAL' => '#DC2626', // Red
            'WARNING' => '#F59E0B',  // Amber
            'AT_RISK' => '#F97316',  // Orange
            'HEALTHY' => '#10B981',  // Green
            default => '#6B7280',    // Gray
        };
    }
}
