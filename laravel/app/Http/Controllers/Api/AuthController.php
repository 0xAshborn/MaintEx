<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Tenant;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;

class AuthController extends Controller
{
    /**
     * Register a new user for an existing tenant.
     * POST /api/auth/register
     *
     * Requires: tenant_id (or subdomain) to link the user to a tenant.
     */
    public function register(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'tenant_id'  => 'required_without:subdomain|integer|exists:core.tenants,tenant_id',
            'subdomain'  => 'required_without:tenant_id|string|exists:core.tenants,subdomain',
            'username'   => 'required|string|max:100',
            'email'      => 'required|email|max:255',
            'password'   => 'required|string|min:8|confirmed',
            'first_name' => 'required|string|max:100',
            'last_name'  => 'required|string|max:100',
            'role_id'    => 'nullable|integer|exists:core.roles,role_id',
        ]);

        // Resolve tenant
        $tenant = isset($validated['tenant_id'])
            ? Tenant::findOrFail($validated['tenant_id'])
            : Tenant::where('subdomain', $validated['subdomain'])->firstOrFail();

        if (!$tenant->is_active) {
            return response()->json(['success' => false, 'message' => 'Tenant is not active.'], 403);
        }

        // Unique checks scoped to this tenant
        if (User::withoutGlobalScopes()->where('tenant_id', $tenant->tenant_id)->where('email', $validated['email'])->exists()) {
            throw ValidationException::withMessages(['email' => ['Email already registered for this tenant.']]);
        }
        if (User::withoutGlobalScopes()->where('tenant_id', $tenant->tenant_id)->where('username', $validated['username'])->exists()) {
            throw ValidationException::withMessages(['username' => ['Username already taken for this tenant.']]);
        }

        $user = User::withoutGlobalScopes()->create([
            'tenant_id'     => $tenant->tenant_id,
            'username'      => $validated['username'],
            'email'         => $validated['email'],
            'password_hash' => Hash::make($validated['password']),
            'first_name'    => $validated['first_name'],
            'last_name'     => $validated['last_name'],
            'role_id'       => $validated['role_id'] ?? $this->getDefaultRoleId($tenant->tenant_id),
            'is_active'     => true,
        ]);

        $token = $user->createToken('api-token')->plainTextToken;

        return response()->json([
            'success' => true,
            'message' => 'User registered successfully',
            'data'    => [
                'user'       => $this->formatUser($user),
                'tenant'     => ['id' => $tenant->tenant_id, 'name' => $tenant->company_name, 'subdomain' => $tenant->subdomain],
                'token'      => $token,
                'token_type' => 'Bearer',
            ],
        ], 201);
    }

    /**
     * Login and get API token.
     * POST /api/auth/login
     *
     * Accepts tenant_id or subdomain to scope the credential lookup.
     */
    public function login(Request $request): JsonResponse
    {
        $request->validate([
            'email'     => 'required|email',
            'password'  => 'required',
            'tenant_id' => 'required_without:subdomain|integer',
            'subdomain' => 'required_without:tenant_id|string',
        ]);

        // Resolve tenant
        $tenant = isset($request->tenant_id)
            ? Tenant::find($request->tenant_id)
            : Tenant::where('subdomain', $request->subdomain)->first();

        if (!$tenant || !$tenant->is_active) {
            throw ValidationException::withMessages(['email' => ['Tenant not found or inactive.']]);
        }

        // Scope the user lookup to this tenant (bypass global scope — not authenticated yet)
        $user = User::withoutGlobalScopes()
            ->where('tenant_id', $tenant->tenant_id)
            ->where('email', $request->email)
            ->where('is_active', true)
            ->first();

        if (!$user || !Hash::check($request->password, $user->password_hash)) {
            throw ValidationException::withMessages([
                'email' => ['The provided credentials are incorrect.'],
            ]);
        }

        $user->update(['last_login' => now()]);
        $token = $user->createToken('api-token')->plainTextToken;

        return response()->json([
            'success' => true,
            'message' => 'Login successful',
            'data'    => [
                'user'       => $this->formatUser($user, true),
                'tenant'     => ['id' => $tenant->tenant_id, 'name' => $tenant->company_name, 'subdomain' => $tenant->subdomain],
                'token'      => $token,
                'token_type' => 'Bearer',
            ],
        ]);
    }

    /**
     * Logout and revoke current token.
     * POST /api/auth/logout
     */
    public function logout(Request $request): JsonResponse
    {
        $request->user()->currentAccessToken()->delete();

        return response()->json(['success' => true, 'message' => 'Logged out successfully']);
    }

    /**
     * Get current user info.
     * GET /api/auth/me
     */
    public function me(Request $request): JsonResponse
    {
        $user = $request->user()->load('role.permissions');

        return response()->json([
            'success' => true,
            'data'    => [
                'id'          => $user->user_id,
                'username'    => $user->username,
                'email'       => $user->email,
                'full_name'   => $user->full_name,
                'tenant_id'   => $user->tenant_id,
                'role'        => $user->role->role_name,
                'permissions' => $user->role->permissions->pluck('permission_name'),
            ],
        ]);
    }

    /**
     * Refresh token.
     * POST /api/auth/refresh
     */
    public function refresh(Request $request): JsonResponse
    {
        $user = $request->user();
        $request->user()->currentAccessToken()->delete();
        $token = $user->createToken('api-token')->plainTextToken;

        return response()->json([
            'success' => true,
            'data'    => ['token' => $token, 'token_type' => 'Bearer'],
        ]);
    }

    // ─── Private helpers ──────────────────────────────────────────────────────

    /**
     * Get default role ID (Technician) scoped to a tenant.
     */
    private function getDefaultRoleId(int $tenantId): int
    {
        // Prefer tenant-specific 'Technician', fallback to global one
        $role = DB::table('core.roles')
            ->where('role_name', 'Technician')
            ->where(function ($q) use ($tenantId) {
                $q->where('tenant_id', $tenantId)->orWhereNull('tenant_id');
            })
            ->orderByRaw('tenant_id IS NULL ASC') // prefer tenant-specific first
            ->first();

        return $role?->role_id ?? DB::table('core.roles')->value('role_id') ?? 1;
    }

    private function formatUser(User $user, bool $includeRole = false): array
    {
        $data = [
            'id'        => $user->user_id,
            'username'  => $user->username,
            'email'     => $user->email,
            'full_name' => $user->full_name,
            'tenant_id' => $user->tenant_id,
        ];
        if ($includeRole) {
            $data['role'] = $user->role?->role_name;
        }
        return $data;
    }
}
