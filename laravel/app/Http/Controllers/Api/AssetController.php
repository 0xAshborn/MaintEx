<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Asset;
use App\Models\DowntimeEvent;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class AssetController extends Controller
{
    /**
     * List all assets with pagination
     * GET /api/assets
     */
    public function index(Request $request): JsonResponse
    {
        $query = Asset::with(['type', 'location']);

        // Filters
        if ($request->has('status')) {
            $query->where('status', $request->input('status'));
        }
        if ($request->has('criticality')) {
            $query->where('criticality', $request->input('criticality'));
        }
        if ($request->has('type_id')) {
            $query->where('asset_type_id', $request->input('type_id'));
        }
        if ($request->has('location_id')) {
            $query->where('location_id', $request->input('location_id'));
        }
        if ($request->has('search')) {
            $search = $request->input('search');
            $query->where(function ($q) use ($search) {
                $q->where('name', 'ilike', "%{$search}%")
                  ->orWhere('tag_number', 'ilike', "%{$search}%")
                  ->orWhere('serial_number', 'ilike', "%{$search}%");
            });
        }

        $assets = $query->paginate($request->input('per_page', 20));

        return response()->json([
            'success' => true,
            'data' => $assets->items(),
            'meta' => [
                'current_page' => $assets->currentPage(),
                'per_page' => $assets->perPage(),
                'total' => $assets->total(),
                'last_page' => $assets->lastPage(),
            ],
        ]);
    }

    /**
     * Get single asset with relationships
     * GET /api/assets/{id}
     */
    public function show(int $id): JsonResponse
    {
        $asset = Asset::with([
            'type',
            'location',
            'readings' => fn($q) => $q->orderByDesc('timestamp')->limit(10),
            'workOrders' => fn($q) => $q->orderByDesc('requested_date')->limit(5),
            'preventiveSchedules' => fn($q) => $q->where('is_active', true),
        ])->findOrFail($id);

        return response()->json([
            'success' => true,
            'data' => $asset,
        ]);
    }

    /**
     * Create new asset
     * POST /api/assets
     */
    public function store(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'name' => 'required|string|max:255',
            'tag_number' => 'required|string|max:100|unique:assets.registry,tag_number',
            'serial_number' => 'nullable|string|max:100',
            'asset_type_id' => 'required|integer|exists:assets.types,asset_type_id',
            'location_id' => 'required|integer|exists:core.locations,location_id',
            'status' => 'string|in:Operational,Down,Maintenance',
            'criticality' => 'string|in:High,Medium,Low',
            'manufacturer' => 'nullable|string|max:100',
            'model' => 'nullable|string|max:100',
            'install_date' => 'nullable|date',
            'purchase_cost' => 'nullable|numeric|min:0',
            'custom_fields' => 'nullable|array',
        ]);

        $asset = Asset::create($validated);

        return response()->json([
            'success' => true,
            'message' => 'Asset created successfully',
            'data' => $asset->load(['type', 'location']),
        ], 201);
    }

    /**
     * Update asset
     * PUT /api/assets/{id}
     */
    public function update(Request $request, int $id): JsonResponse
    {
        $asset = Asset::findOrFail($id);

        $validated = $request->validate([
            'name' => 'string|max:255',
            'tag_number' => "string|max:100|unique:assets.registry,tag_number,{$id},asset_id",
            'serial_number' => 'nullable|string|max:100',
            'asset_type_id' => 'integer|exists:assets.types,asset_type_id',
            'location_id' => 'integer|exists:core.locations,location_id',
            'status' => 'string|in:Operational,Down,Maintenance',
            'criticality' => 'string|in:High,Medium,Low',
            'manufacturer' => 'nullable|string|max:100',
            'model' => 'nullable|string|max:100',
            'install_date' => 'nullable|date',
            'purchase_cost' => 'nullable|numeric|min:0',
            'custom_fields' => 'nullable|array',
        ]);

        $asset->update($validated);

        return response()->json([
            'success' => true,
            'message' => 'Asset updated successfully',
            'data' => $asset->fresh(['type', 'location']),
        ]);
    }

    /**
     * Delete asset
     * DELETE /api/assets/{id}
     */
    public function destroy(int $id): JsonResponse
    {
        $asset = Asset::findOrFail($id);
        $asset->delete();

        return response()->json([
            'success' => true,
            'message' => 'Asset deleted successfully',
        ]);
    }

    /**
     * Record downtime event
     * POST /api/assets/{id}/downtime
     */
    public function recordDowntime(Request $request, int $id): JsonResponse
    {
        $asset = Asset::findOrFail($id);

        $validated = $request->validate([
            'started_at' => 'required|date',
            'ended_at' => 'nullable|date|after:started_at',
            'reason' => 'required|string|in:Breakdown,PM,Changeover,Setup',
            'failure_code' => 'nullable|string|max:100',
            'wo_id' => 'nullable|integer|exists:maintenance.work_orders,wo_id',
            'notes' => 'nullable|string',
        ]);

        $validated['asset_id'] = $id;
        $validated['created_by'] = auth()->id();

        $downtime = DowntimeEvent::create($validated);

        // Update asset status if breakdown
        if ($validated['reason'] === 'Breakdown' && !isset($validated['ended_at'])) {
            $asset->update(['status' => 'Down']);
        }

        return response()->json([
            'success' => true,
            'message' => 'Downtime event recorded',
            'data' => $downtime,
        ], 201);
    }

    /**
     * End downtime event
     * PUT /api/assets/{id}/downtime/{eventId}/end
     */
    public function endDowntime(int $id, int $eventId): JsonResponse
    {
        $downtime = DowntimeEvent::where('asset_id', $id)
            ->where('event_id', $eventId)
            ->whereNull('ended_at')
            ->firstOrFail();

        $downtime->update(['ended_at' => now()]);

        // Check if we can set asset back to Operational
        $hasActiveDowntime = DowntimeEvent::where('asset_id', $id)
            ->whereNull('ended_at')
            ->exists();

        if (!$hasActiveDowntime) {
            Asset::where('asset_id', $id)->update(['status' => 'Operational']);
        }

        return response()->json([
            'success' => true,
            'message' => 'Downtime ended',
            'data' => $downtime->fresh(),
        ]);
    }
}
