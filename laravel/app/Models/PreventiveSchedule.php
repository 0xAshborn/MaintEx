<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * PreventiveSchedule Model (maintenance.preventive_schedule table)
 */
class PreventiveSchedule extends Model
{
    protected $table = 'maintenance.preventive_schedule';
    protected $primaryKey = 'pm_id';
    public $timestamps = false;

    protected $fillable = [
        'name',
        'description',
        'asset_id',
        'schedule_type',
        'interval_value',
        'interval_unit',
        'next_due_date',
        'next_due_meter',
        'is_active',
    ];

    protected $casts = [
        'next_due_date' => 'date',
        'is_active' => 'boolean',
        'interval_value' => 'decimal:2',
        'next_due_meter' => 'decimal:2',
    ];

    public function asset(): BelongsTo
    {
        return $this->belongsTo(Asset::class, 'asset_id', 'asset_id');
    }

    // Scopes
    public function scopeActive($query)
    {
        return $query->where('is_active', true);
    }

    public function scopeOverdue($query)
    {
        return $query->where('is_active', true)
                     ->where('next_due_date', '<', now());
    }

    public function scopeDueSoon($query, $days = 7)
    {
        return $query->where('is_active', true)
                     ->whereBetween('next_due_date', [now(), now()->addDays($days)]);
    }
}
