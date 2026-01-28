<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\WorkOrder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class WorkOrderController extends Controller
{
    /**
     * List work orders with filters
     * GET /api/work-orders
     */
    public function index(Request $request): JsonResponse
    {
        $query = WorkOrder::with(['asset', 'location', 'assignedTo', 'reportedBy']);

        // Filters
        if ($request->has('status')) {
            $query->where('status', $request->input('status'));
        }
        if ($request->has('priority')) {
            $query->where('priority', $request->input('priority'));
        }
        if ($request->has('type')) {
            $query->where('type', $request->input('type'));
        }
        if ($request->has('asset_id')) {
            $query->where('asset_id', $request->input('asset_id'));
        }
        if ($request->has('assigned_to')) {
            $query->where('assigned_to_id', $request->input('assigned_to'));
        }
        if ($request->boolean('overdue')) {
            $query->overdue();
        }
        if ($request->boolean('open')) {
            $query->open();
        }

        // Sorting
        $sortBy = $request->input('sort_by', 'requested_date');
        $sortDir = $request->input('sort_dir', 'desc');
        $query->orderBy($sortBy, $sortDir);

        $workOrders = $query->paginate($request->input('per_page', 20));

        return response()->json([
            'success' => true,
            'data' => $workOrders->items(),
            'meta' => [
                'current_page' => $workOrders->currentPage(),
                'per_page' => $workOrders->perPage(),
                'total' => $workOrders->total(),
            ],
        ]);
    }

    /**
     * Get single work order
     * GET /api/work-orders/{id}
     */
    public function show(int $id): JsonResponse
    {
        $wo = WorkOrder::with([
            'asset',
            'location',
            'assignedTo',
            'reportedBy',
            'preventiveSchedule',
            'partUsages.part',
            'tasks.task',
        ])->findOrFail($id);

        return response()->json([
            'success' => true,
            'data' => $wo,
        ]);
    }

    /**
     * Create work order
     * POST /api/work-orders
     */
    public function store(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'title' => 'required|string|max:255',
            'description' => 'nullable|string',
            'type' => 'required|string|in:PM,Corrective,Inspection',
            'asset_id' => 'required|integer|exists:assets.registry,asset_id',
            'location_id' => 'nullable|integer|exists:core.locations,location_id',
            'assigned_to_id' => 'nullable|integer|exists:core.users,user_id',
            'pm_id' => 'nullable|integer|exists:maintenance.preventive_schedule,pm_id',
            'priority' => 'string|in:Low,Medium,High,Urgent',
            'status' => 'string|in:Draft,Open,In Progress,Complete,On Hold',
            'due_date' => 'nullable|date',
        ]);

        $validated['reported_by_id'] = auth()->id();

        $wo = WorkOrder::create($validated);

        return response()->json([
            'success' => true,
            'message' => 'Work order created',
            'data' => $wo->load(['asset', 'location']),
        ], 201);
    }

    /**
     * Update work order
     * PUT /api/work-orders/{id}
     */
    public function update(Request $request, int $id): JsonResponse
    {
        $wo = WorkOrder::findOrFail($id);

        $validated = $request->validate([
            'title' => 'string|max:255',
            'description' => 'nullable|string',
            'type' => 'string|in:PM,Corrective,Inspection',
            'assigned_to_id' => 'nullable|integer|exists:core.users,user_id',
            'priority' => 'string|in:Low,Medium,High,Urgent',
            'status' => 'string|in:Draft,Open,In Progress,Complete,On Hold,Cancelled',
            'due_date' => 'nullable|date',
            'labor_cost' => 'nullable|numeric|min:0',
            'material_cost' => 'nullable|numeric|min:0',
        ]);

        // Track status transitions
        if (isset($validated['status'])) {
            if ($validated['status'] === 'In Progress' && !$wo->start_time) {
                $validated['start_time'] = now();
            }
            if ($validated['status'] === 'Complete' && !$wo->completion_time) {
                $validated['completion_time'] = now();
            }
        }

        $wo->update($validated);

        return response()->json([
            'success' => true,
            'message' => 'Work order updated',
            'data' => $wo->fresh(['asset', 'location', 'assignedTo']),
        ]);
    }

    /**
     * Delete work order
     * DELETE /api/work-orders/{id}
     */
    public function destroy(int $id): JsonResponse
    {
        $wo = WorkOrder::findOrFail($id);
        $wo->delete();

        return response()->json([
            'success' => true,
            'message' => 'Work order deleted',
        ]);
    }

    /**
     * Quick action: Start work order
     * POST /api/work-orders/{id}/start
     */
    public function start(int $id): JsonResponse
    {
        $wo = WorkOrder::findOrFail($id);
        
        $wo->update([
            'status' => 'In Progress',
            'start_time' => now(),
        ]);

        return response()->json([
            'success' => true,
            'message' => 'Work order started',
            'data' => $wo->fresh(),
        ]);
    }

    /**
     * Quick action: Complete work order
     * POST /api/work-orders/{id}/complete
     */
    public function complete(Request $request, int $id): JsonResponse
    {
        $wo = WorkOrder::findOrFail($id);
        
        $validated = $request->validate([
            'labor_cost' => 'nullable|numeric|min:0',
            'material_cost' => 'nullable|numeric|min:0',
        ]);

        $wo->update(array_merge($validated, [
            'status' => 'Complete',
            'completion_time' => now(),
        ]));

        return response()->json([
            'success' => true,
            'message' => 'Work order completed',
            'data' => $wo->fresh(),
        ]);
    }
}
