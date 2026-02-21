<?php

namespace App\Models\Scopes;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Scope;

/**
 * TenantScope — Global Eloquent scope that restricts all queries
 * to the currently authenticated user's tenant_id.
 *
 * This is the SECOND layer of defense (PG RLS is the first).
 * Applied automatically via each model's booted() method.
 */
class TenantScope implements Scope
{
    /**
     * Apply the scope to a given Eloquent query builder.
     */
    public function apply(Builder $builder, Model $model): void
    {
        $tenantId = self::getCurrentTenantId();

        if ($tenantId !== null) {
            $builder->where($model->getTable() . '.tenant_id', $tenantId);
        }
    }

    /**
     * Resolve the current tenant ID from:
     * 1. Request binding (set by SetTenantContext middleware)
     * 2. Authenticated user's tenant_id (fallback)
     */
    public static function getCurrentTenantId(): ?int
    {
        // Primary: from request attribute (set by middleware)
        if (app()->bound('current_tenant_id')) {
            return app('current_tenant_id');
        }

        // Fallback: from the authenticated user
        if (auth()->check()) {
            return auth()->user()->tenant_id ?? null;
        }

        return null;
    }
}
