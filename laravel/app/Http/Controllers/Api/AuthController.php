<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;

class AuthController extends Controller
{
    /**
     * Register a new user
     * POST /api/auth/register
     */
    public function register(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'username'   => 'required|string|max:100|unique:core.users,username',
            'email'      => 'required|email|max:255|unique:core.users,email',
            'password'   => 'required|string|min:8|confirmed',
            'first_name' => 'required|string|max:100',
            'last_name'  => 'required|string|max:100',
            'role_id'    => 'nullable|integer|exists:core.roles,role_id',
        ]);

        $user = User::create([
            'username'      => $validated['username'],
            'email'         => $validated['email'],
            'password_hash' => Hash::make($validated['password']),
            'first_name'    => $validated['first_name'],
            'last_name'     => $validated['last_name'],
            'role_id'       => $validated['role_id'] ?? $this->getDefaultRoleId(),
            'is_active'     => true,
        ]);

        $token = $user->createToken('api-token')->plainTextToken;

        return response()->json([
            'success' => true,
            'message' => 'User registered successfully',
            'data' => [
                'user' => [
                    'id'        => $user->user_id,
                    'username'  => $user->username,
                    'email'     => $user->email,
                    'full_name' => $user->full_name,
                ],
                'token'      => $token,
                'token_type' => 'Bearer',
            ],
        ], 201);
    }

    /**
     * Login and get API token
     * POST /api/auth/login
     */
    public function login(Request $request): JsonResponse
    {
        $request->validate([
            'email' => 'required|email',
            'password' => 'required',
        ]);

        $user = User::where('email', $request->email)
            ->where('is_active', true)
            ->first();

        if (!$user || !Hash::check($request->password, $user->password_hash)) {
            throw ValidationException::withMessages([
                'email' => ['The provided credentials are incorrect.'],
            ]);
        }

        // Update last login
        $user->update(['last_login' => now()]);

        // Create token
        $token = $user->createToken('api-token')->plainTextToken;

        return response()->json([
            'success' => true,
            'message' => 'Login successful',
            'data' => [
                'user' => [
                    'id' => $user->user_id,
                    'username' => $user->username,
                    'email' => $user->email,
                    'full_name' => $user->full_name,
                    'role' => $user->role->role_name,
                ],
                'token' => $token,
                'token_type' => 'Bearer',
            ],
        ]);
    }

    /**
     * Logout and revoke token
     * POST /api/auth/logout
     */
    public function logout(Request $request): JsonResponse
    {
        $request->user()->currentAccessToken()->delete();

        return response()->json([
            'success' => true,
            'message' => 'Logged out successfully',
        ]);
    }

    /**
     * Get current user info
     * GET /api/auth/me
     */
    public function me(Request $request): JsonResponse
    {
        $user = $request->user()->load('role.permissions');

        return response()->json([
            'success' => true,
            'data' => [
                'id' => $user->user_id,
                'username' => $user->username,
                'email' => $user->email,
                'full_name' => $user->full_name,
                'role' => $user->role->role_name,
                'permissions' => $user->role->permissions->pluck('permission_name'),
            ],
        ]);
    }

    /**
     * Refresh token
     * POST /api/auth/refresh
     */
    public function refresh(Request $request): JsonResponse
    {
        $user = $request->user();
        
        // Revoke current token
        $request->user()->currentAccessToken()->delete();
        
        // Create new token
        $token = $user->createToken('api-token')->plainTextToken;

        return response()->json([
            'success' => true,
            'data' => [
                'token' => $token,
                'token_type' => 'Bearer',
            ],
        ]);
    }

    /**
     * Get default role ID (Technician or first available)
     */
    private function getDefaultRoleId(): int
    {
        $role = DB::table('core.roles')
            ->where('role_name', 'Technician')
            ->first();

        return $role?->role_id ?? DB::table('core.roles')->value('role_id') ?? 1;
    }
}
