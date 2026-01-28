<?php

namespace App\Models;

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
        'is_active' => 'boolean',
        'last_login' => 'datetime',
        'created_at' => 'datetime',
    ];

    // Laravel expects 'password' but we use 'password_hash'
    public function getAuthPassword()
    {
        return $this->password_hash;
    }

    // Relationships
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
