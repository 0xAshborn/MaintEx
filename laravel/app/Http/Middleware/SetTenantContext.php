<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpFoundation\Response;

/**
 * SetTenantContext Middleware
 *
 * Runs after Sanctum resolves the authenticated user.
 * Does two things:
 *  1. Binds tenant_id into the Laravel service container so TenantScope can use it.
 *  2. Sets the PostgreSQL session variable `app.current_tenant` so RLS policies activate.
 *
 * IMPORTANT: This must run INSIDE the `auth:sanctum` middleware group, not before it.
 */
class SetTenantContext
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();

        if ($user && $user->tenant_id) {
            $tenantId = (int) $user->tenant_id;

            // 1. Make tenant_id available to TenantScope globally (ORM layer)
            app()->instance('current_tenant_id', $tenantId);

            // 2. Activate PostgreSQL RLS for this connection (DB layer)
            //    SET LOCAL only persists for the current transaction.
            //    We use SET (session) so it survives multiple statements in the request.
            DB::statement("SET app.current_tenant = ?", [$tenantId]);
        }

        $response = $next($request);

        // Clean up the PG session variable after the request completes
        // (belt-and-suspenders: connection pooling can reuse connections)
        if ($user && $user->tenant_id) {
            DB::statement("RESET app.current_tenant");
        }

        return $response;
    }
}
