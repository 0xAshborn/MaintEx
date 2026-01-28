<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * AssetType Model (assets.types table)
 */
class AssetType extends Model
{
    protected $table = 'assets.types';
    protected $primaryKey = 'asset_type_id';
    public $timestamps = false;

    protected $fillable = ['name', 'description'];

    public function assets(): HasMany
    {
        return $this->hasMany(Asset::class, 'asset_type_id', 'asset_type_id');
    }
}
