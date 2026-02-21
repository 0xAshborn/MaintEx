<?php

namespace App\Models;

use App\Models\Scopes\TenantScope;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Asset Model (assets.registry table)
 */
class Asset extends Model
{
    protected $table = 'assets.registry';
    protected $primaryKey = 'asset_id';
    public $timestamps = false;

    protected $fillable = [
        'tenant_id',
        'name',
        'tag_number',
        'serial_number',
        'asset_type_id',
        'location_id',
        'status',
        'criticality',
        'manufacturer',
        'model',
        'install_date',
        'purchase_cost',
        'last_meter_reading',
        'custom_fields',
    ];

    protected $casts = [
        'custom_fields'  => 'array',
        'install_date'   => 'date',
        'purchase_cost'  => 'decimal:2',
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

    public function type(): BelongsTo
    {
        return $this->belongsTo(AssetType::class, 'asset_type_id', 'asset_type_id');
    }

    public function location(): BelongsTo
    {
        return $this->belongsTo(Location::class, 'location_id', 'location_id');
    }

    public function workOrders(): HasMany
    {
        return $this->hasMany(WorkOrder::class, 'asset_id', 'asset_id');
    }

    public function readings(): HasMany
    {
        return $this->hasMany(AssetReading::class, 'asset_id', 'asset_id');
    }

    public function downtimeEvents(): HasMany
    {
        return $this->hasMany(DowntimeEvent::class, 'asset_id', 'asset_id');
    }

    public function preventiveSchedules(): HasMany
    {
        return $this->hasMany(PreventiveSchedule::class, 'asset_id', 'asset_id');
    }

    // Scopes
    public function scopeOperational($query)
    {
        return $query->where('status', 'Operational');
    }

    public function scopeCritical($query)
    {
        return $query->where('criticality', 'High');
    }

    public function scopeDown($query)
    {
        return $query->where('status', 'Down');
    }
}
