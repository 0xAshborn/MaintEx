<?php

namespace App\Models;

use App\Models\Scopes\TenantScope;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Role Model (core.roles table)
 *
 * Special scoping rule:
 *   tenant_id = NULL  → Global Synaptia-managed role (visible to ALL tenants, read-only)
 *   tenant_id = X     → Role owned by tenant X
 *
 * The scope shows BOTH the tenant's own roles AND the global NULL ones.
 */
class Role extends Model
{
    protected $table = 'core.roles';
    protected $primaryKey = 'role_id';
    public $timestamps = false;

    protected $fillable = [
        'tenant_id',
        'role_name',
        'description',
    ];

    protected static function booted(): void
    {
        // Custom scope: tenant's own roles + global (NULL) roles
        static::addGlobalScope('tenant_roles', function (Builder $builder) {
            $tenantId = \App\Models\Scopes\TenantScope::getCurrentTenantId();
            if ($tenantId !== null) {
                $builder->where(function (Builder $q) use ($tenantId) {
                    $q->where('core.roles.tenant_id', $tenantId)
                      ->orWhereNull('core.roles.tenant_id');
                });
            }
        });
    }

    // Relationships
    public function tenant(): BelongsTo
    {
        return $this->belongsTo(Tenant::class, 'tenant_id', 'tenant_id');
    }

    public function users(): HasMany
    {
        return $this->hasMany(User::class, 'role_id', 'role_id');
    }

    public function permissions(): BelongsToMany
    {
        return $this->belongsToMany(
            Permission::class,
            'core.role_permissions',
            'role_id',
            'permission_id'
        );
    }

    // Helpers
    public function isGlobal(): bool
    {
        return is_null($this->tenant_id);
    }
}
