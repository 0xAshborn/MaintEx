<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Tenant Model (core.tenants table)
 * Root B2B client entity. Every piece of data belongs to a tenant.
 */
class Tenant extends Model
{
    protected $table = 'core.tenants';
    protected $primaryKey = 'tenant_id';
    public $timestamps = false;

    protected $fillable = [
        'company_name',
        'subdomain',
        'plan',
        'is_active',
    ];

    protected $casts = [
        'is_active' => 'boolean',
        'created_at' => 'datetime',
    ];

    public function users(): HasMany
    {
        return $this->hasMany(User::class, 'tenant_id', 'tenant_id');
    }

    public function roles(): HasMany
    {
        return $this->hasMany(Role::class, 'tenant_id', 'tenant_id');
    }
}
