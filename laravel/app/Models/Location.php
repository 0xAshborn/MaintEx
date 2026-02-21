<?php

namespace App\Models;

use App\Models\Scopes\TenantScope;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Location Model (core.locations table)
 * Hierarchical: Sites → Buildings → Zones
 */
class Location extends Model
{
    protected $table = 'core.locations';
    protected $primaryKey = 'location_id';
    public $timestamps = false;

    protected $fillable = [
        'tenant_id',
        'name',
        'address',
        'parent_location_id',
        'latitude',
        'longitude',
    ];

    protected $casts = [
        'latitude'  => 'decimal:8',
        'longitude' => 'decimal:8',
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

    public function parent(): BelongsTo
    {
        return $this->belongsTo(Location::class, 'parent_location_id', 'location_id');
    }

    public function children(): HasMany
    {
        return $this->hasMany(Location::class, 'parent_location_id', 'location_id');
    }

    public function assets(): HasMany
    {
        return $this->hasMany(Asset::class, 'location_id', 'location_id');
    }
}
