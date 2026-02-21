<?php

namespace App\Models;

use App\Models\Scopes\TenantScope;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

/**
 * User Model (core.users table)
 */
class User extends Authenticatable
{
    use HasApiTokens, Notifiable;

    protected $table = 'core.users';
    protected $primaryKey = 'user_id';
    public $timestamps = false;

    protected $fillable = [
        'tenant_id',
        'username',
        'email',
        'password_hash',
        'first_name',
        'last_name',
        'role_id',
        'is_active',
    ];

    protected $hidden = [
        'password_hash',
    ];

    protected $casts = [
        'is_active'  => 'boolean',
        'last_login' => 'datetime',
        'created_at' => 'datetime',
    ];

    /**
     * Boot: apply TenantScope to all queries automatically.
     */
    protected static function booted(): void
    {
        static::addGlobalScope(new TenantScope());

        // Auto-inject tenant_id on create
        static::creating(function (self $user) {
            if (empty($user->tenant_id) && auth()->check()) {
                $user->tenant_id = auth()->user()->tenant_id;
            }
        });
    }

    // Laravel password accessor
    public function getAuthPassword()
    {
        return $this->password_hash;
    }

    // Relationships
    public function tenant(): BelongsTo
    {
        return $this->belongsTo(Tenant::class, 'tenant_id', 'tenant_id');
    }

    public function role(): BelongsTo
    {
        return $this->belongsTo(Role::class, 'role_id', 'role_id');
    }

    public function assignedWorkOrders(): HasMany
    {
        return $this->hasMany(WorkOrder::class, 'assigned_to_id', 'user_id');
    }

    public function reportedWorkOrders(): HasMany
    {
        return $this->hasMany(WorkOrder::class, 'reported_by_id', 'user_id');
    }

    // Helpers
    public function getFullNameAttribute(): string
    {
        return trim("{$this->first_name} {$this->last_name}");
    }

    public function hasPermission(string $permission): bool
    {
        return $this->role->permissions()
            ->where('permission_name', $permission)
            ->exists();
    }
}
