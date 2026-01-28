<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * WorkOrder Model (maintenance.work_orders table)
 */
class WorkOrder extends Model
{
    protected $table = 'maintenance.work_orders';
    protected $primaryKey = 'wo_id';
    public $timestamps = false;

    protected $fillable = [
        'title',
        'description',
        'type',
        'asset_id',
        'location_id',
        'reported_by_id',
        'assigned_to_id',
        'pm_id',
        'priority',
        'status',
        'requested_date',
        'due_date',
        'start_time',
        'completion_time',
        'labor_cost',
        'material_cost',
    ];

    protected $casts = [
        'requested_date' => 'datetime',
        'due_date' => 'datetime',
        'start_time' => 'datetime',
        'completion_time' => 'datetime',
        'labor_cost' => 'decimal:2',
        'material_cost' => 'decimal:2',
        'total_cost' => 'decimal:2',
    ];

    // Relationships
    public function asset(): BelongsTo
    {
        return $this->belongsTo(Asset::class, 'asset_id', 'asset_id');
    }

    public function location(): BelongsTo
    {
        return $this->belongsTo(Location::class, 'location_id', 'location_id');
    }

    public function reportedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'reported_by_id', 'user_id');
    }

    public function assignedTo(): BelongsTo
    {
        return $this->belongsTo(User::class, 'assigned_to_id', 'user_id');
    }

    public function preventiveSchedule(): BelongsTo
    {
        return $this->belongsTo(PreventiveSchedule::class, 'pm_id', 'pm_id');
    }

    public function partUsages(): HasMany
    {
        return $this->hasMany(PartUsage::class, 'wo_id', 'wo_id');
    }

    public function tasks(): HasMany
    {
        return $this->hasMany(WoTask::class, 'wo_id', 'wo_id');
    }

    // Scopes
    public function scopeOpen($query)
    {
        return $query->whereNotIn('status', ['Complete', 'Cancelled']);
    }

    public function scopeComplete($query)
    {
        return $query->where('status', 'Complete');
    }

    public function scopeOverdue($query)
    {
        return $query->where('due_date', '<', now())
                     ->whereNotIn('status', ['Complete', 'Cancelled']);
    }

    public function scopeHighPriority($query)
    {
        return $query->whereIn('priority', ['High', 'Urgent']);
    }
}
