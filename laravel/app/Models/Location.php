<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Location Model (core.locations table)
 */
class Location extends Model
{
    protected $table = 'core.locations';
    protected $primaryKey = 'location_id';
    public $timestamps = false;

    protected $fillable = [
        'name',
        'address',
        'parent_location_id',
        'latitude',
        'longitude',
    ];

    protected $casts = [
        'latitude' => 'decimal:8',
        'longitude' => 'decimal:8',
    ];

    // Self-referential for hierarchy
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
