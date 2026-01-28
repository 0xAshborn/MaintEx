<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Permission Model (core.permissions table)
 */
class Permission extends Model
{
    protected $table = 'core.permissions';
    protected $primaryKey = 'permission_id';
    public $timestamps = false;

    protected $fillable = ['permission_name'];
}
