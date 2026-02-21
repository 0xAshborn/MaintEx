<?php

namespace App\Models;

use App\Models\Scopes\TenantScope;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * AssetType Model (assets.types table)
 */
class AssetType extends Model
{
    protected $table = 'assets.types';
    protected $primaryKey = 'asset_type_id';
    public $timestamps = false;

    protected $fillable = [
        'tenant_id',
        'name',
        'description',
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

    public function assets(): HasMany
    {
        return $this->hasMany(Asset::class, 'asset_type_id', 'asset_type_id');
    }
}
