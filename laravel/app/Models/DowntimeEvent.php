<?php

namespace App\Models;

use App\Models\Scopes\TenantScope;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * DowntimeEvent Model (assets.downtime_events table)
 * Critical for KPI calculations (MTTR, MTBF, Availability)
 */
class DowntimeEvent extends Model
{
    protected $table = 'assets.downtime_events';
    protected $primaryKey = 'event_id';
    public $timestamps = false;

    protected $fillable = [
        'tenant_id',
        'asset_id',
        'started_at',
        'ended_at',
        'reason',
        'failure_code',
        'wo_id',
        'notes',
        'created_by',
    ];

    protected $casts = [
        'started_at'     => 'datetime',
        'ended_at'       => 'datetime',
        'created_at'     => 'datetime',
        'duration_hours' => 'decimal:2',
    ];

    protected static function booted(): void
    {
        static::addGlobalScope(new TenantScope());

        static::creating(function (self $model) {
            if (empty($model->tenant_id) && auth()->check()) {
                $model->tenant_id = auth()->user()->tenant_id;
            }
        });
    }

    // Relationships
    public function tenant(): BelongsTo
    {
        return $this->belongsTo(Tenant::class, 'tenant_id', 'tenant_id');
    }

    public function asset(): BelongsTo
    {
        return $this->belongsTo(Asset::class, 'asset_id', 'asset_id');
    }

    public function workOrder(): BelongsTo
    {
        return $this->belongsTo(WorkOrder::class, 'wo_id', 'wo_id');
    }

    public function createdBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by', 'user_id');
    }

    // Scopes
    public function scopeBreakdowns($query)
    {
        return $query->where('reason', 'Breakdown');
    }

    public function scopeActive($query)
    {
        return $query->whereNull('ended_at');
    }

    public function scopeInPeriod($query, $startDate, $endDate)
    {
        return $query->whereBetween('started_at', [$startDate, $endDate]);
    }
}
