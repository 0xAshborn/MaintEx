<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\PreventiveSchedule;
use App\Models\WorkOrder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Carbon\Carbon;

/**
 * Calendar API for Preventive Maintenance Scheduling
 * 
 * Supports drag-and-drop rescheduling for calendar interfaces
 * (FullCalendar, React Big Calendar, etc.)
 */
class CalendarController extends Controller
{
    /**
     * Get all calendar events (PM schedules + Work Orders)
     * 
     * GET /api/calendar/events
     * Query: start, end (ISO dates for range), type (pm|wo|all)
     */
    public function events(Request $request): JsonResponse
    {
        $start = $request->input('start') 
            ? Carbon::parse($request->input('start')) 
            : Carbon::now()->startOfMonth();
        
        $end = $request->input('end') 
            ? Carbon::parse($request->input('end')) 
            : Carbon::now()->endOfMonth();
        
        $type = $request->input('type', 'all');
        
        $events = [];

        // Get PM Schedules
        if ($type === 'all' || $type === 'pm') {
            $pmEvents = $this->getPmEvents($start, $end);
            $events = array_merge($events, $pmEvents);
        }

        // Get Work Orders
        if ($type === 'all' || $type === 'wo') {
            $woEvents = $this->getWoEvents($start, $end);
            $events = array_merge($events, $woEvents);
        }

        return response()->json([
            'success' => true,
            'data' => $events,
            'meta' => [
                'start' => $start->toDateString(),
                'end' => $end->toDateString(),
                'count' => count($events),
            ],
        ]);
    }

    /**
     * Get only PM schedule events
     * 
     * GET /api/calendar/pm
     */
    public function pmSchedules(Request $request): JsonResponse
    {
        $start = $request->input('start') 
            ? Carbon::parse($request->input('start')) 
            : Carbon::now()->startOfMonth();
        
        $end = $request->input('end') 
            ? Carbon::parse($request->input('end')) 
            : Carbon::now()->addMonths(3);

        $schedules = PreventiveSchedule::with(['asset.type', 'asset.location'])
            ->where('is_active', true)
            ->whereBetween('next_due_date', [$start, $end])
            ->orderBy('next_due_date')
            ->get();

        $events = $schedules->map(function ($pm) {
            return $this->formatPmEvent($pm);
        });

        return response()->json([
            'success' => true,
            'data' => $events,
        ]);
    }

    /**
     * Reschedule PM via drag-and-drop
     * 
     * PUT /api/calendar/pm/{id}/reschedule
     * Body: { "new_date": "2024-12-25" }
     */
    public function reschedule(Request $request, int $id): JsonResponse
    {
        $pm = PreventiveSchedule::findOrFail($id);

        $validated = $request->validate([
            'new_date' => 'required|date',
        ]);

        $oldDate = $pm->next_due_date;
        $newDate = Carbon::parse($validated['new_date']);

        $pm->update([
            'next_due_date' => $newDate,
        ]);

        return response()->json([
            'success' => true,
            'message' => 'PM rescheduled successfully',
            'data' => [
                'pm_id' => $pm->pm_id,
                'name' => $pm->name,
                'old_date' => $oldDate?->toDateString(),
                'new_date' => $newDate->toDateString(),
                'asset' => $pm->asset->name ?? null,
            ],
        ]);
    }

    /**
     * Batch reschedule multiple PMs (for multi-select drag)
     * 
     * PUT /api/calendar/pm/batch-reschedule
     * Body: { "changes": [{ "pm_id": 1, "new_date": "2024-12-25" }, ...] }
     */
    public function batchReschedule(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'changes' => 'required|array|min:1',
            'changes.*.pm_id' => 'required|integer|exists:maintenance.preventive_schedule,pm_id',
            'changes.*.new_date' => 'required|date',
        ]);

        $results = [];

        foreach ($validated['changes'] as $change) {
            $pm = PreventiveSchedule::find($change['pm_id']);
            $oldDate = $pm->next_due_date;
            
            $pm->update([
                'next_due_date' => Carbon::parse($change['new_date']),
            ]);

            $results[] = [
                'pm_id' => $pm->pm_id,
                'name' => $pm->name,
                'old_date' => $oldDate?->toDateString(),
                'new_date' => $change['new_date'],
            ];
        }

        return response()->json([
            'success' => true,
            'message' => count($results) . ' PM(s) rescheduled',
            'data' => $results,
        ]);
    }

    /**
     * Get unscheduled PMs (no next_due_date)
     * 
     * GET /api/calendar/pm/unscheduled
     */
    public function unscheduled(): JsonResponse
    {
        $unscheduled = PreventiveSchedule::with(['asset.type'])
            ->where('is_active', true)
            ->whereNull('next_due_date')
            ->get()
            ->map(function ($pm) {
                return [
                    'id' => $pm->pm_id,
                    'title' => $pm->name,
                    'asset_id' => $pm->asset_id,
                    'asset_name' => $pm->asset->name ?? 'Unknown',
                    'asset_type' => $pm->asset->type->name ?? null,
                    'schedule_type' => $pm->schedule_type,
                    'interval' => $pm->interval_value . ' ' . $pm->interval_unit,
                    'draggable' => true,
                ];
            });

        return response()->json([
            'success' => true,
            'data' => $unscheduled,
        ]);
    }

    /**
     * Get overdue PMs
     * 
     * GET /api/calendar/pm/overdue
     */
    public function overdue(): JsonResponse
    {
        $overdue = PreventiveSchedule::with(['asset.type', 'asset.location'])
            ->where('is_active', true)
            ->whereNotNull('next_due_date')
            ->where('next_due_date', '<', Carbon::today())
            ->orderBy('next_due_date')
            ->get()
            ->map(function ($pm) {
                $daysOverdue = Carbon::parse($pm->next_due_date)->diffInDays(Carbon::today());
                return [
                    'id' => $pm->pm_id,
                    'title' => $pm->name,
                    'asset_name' => $pm->asset->name ?? 'Unknown',
                    'due_date' => $pm->next_due_date->toDateString(),
                    'days_overdue' => $daysOverdue,
                    'urgency' => $daysOverdue > 7 ? 'critical' : ($daysOverdue > 3 ? 'high' : 'medium'),
                ];
            });

        return response()->json([
            'success' => true,
            'data' => $overdue,
            'count' => $overdue->count(),
        ]);
    }

    /**
     * Format PM schedule as calendar event
     */
    private function formatPmEvent(PreventiveSchedule $pm): array
    {
        $isOverdue = $pm->next_due_date && $pm->next_due_date < Carbon::today();
        
        return [
            // Standard calendar event fields
            'id' => 'pm_' . $pm->pm_id,
            'resourceId' => $pm->pm_id,
            'title' => $pm->name,
            'start' => $pm->next_due_date?->toDateString(),
            'end' => $pm->next_due_date?->toDateString(),
            'allDay' => true,
            
            // Styling
            'backgroundColor' => $isOverdue ? '#DC2626' : '#3B82F6',
            'borderColor' => $isOverdue ? '#991B1B' : '#1D4ED8',
            'textColor' => '#FFFFFF',
            'classNames' => $isOverdue ? ['pm-overdue'] : ['pm-scheduled'],
            
            // Drag-and-drop config
            'editable' => true,
            'durationEditable' => false,
            
            // Extended properties
            'extendedProps' => [
                'type' => 'pm',
                'pm_id' => $pm->pm_id,
                'asset_id' => $pm->asset_id,
                'asset_name' => $pm->asset->name ?? 'Unknown',
                'asset_tag' => $pm->asset->tag_number ?? null,
                'asset_type' => $pm->asset->type->name ?? null,
                'location' => $pm->asset->location->name ?? null,
                'schedule_type' => $pm->schedule_type,
                'interval' => $pm->interval_value . ' ' . $pm->interval_unit,
                'is_overdue' => $isOverdue,
                'description' => $pm->description,
            ],
        ];
    }

    /**
     * Get PM events in date range
     */
    private function getPmEvents(Carbon $start, Carbon $end): array
    {
        $schedules = PreventiveSchedule::with(['asset.type', 'asset.location'])
            ->where('is_active', true)
            ->whereBetween('next_due_date', [$start, $end])
            ->get();

        return $schedules->map(fn($pm) => $this->formatPmEvent($pm))->toArray();
    }

    /**
     * Get Work Order events in date range
     */
    private function getWoEvents(Carbon $start, Carbon $end): array
    {
        $workOrders = WorkOrder::with(['asset', 'assignedTo'])
            ->where(function ($query) use ($start, $end) {
                $query->whereBetween('due_date', [$start, $end])
                      ->orWhereBetween('requested_date', [$start, $end]);
            })
            ->get();

        return $workOrders->map(function ($wo) {
            $isOverdue = $wo->due_date && $wo->due_date < Carbon::now() 
                && !in_array($wo->status, ['Complete', 'Cancelled']);
            
            $color = match($wo->priority) {
                'Urgent' => '#DC2626',
                'High' => '#F59E0B',
                'Medium' => '#10B981',
                'Low' => '#6B7280',
                default => '#3B82F6',
            };
            
            return [
                'id' => 'wo_' . $wo->wo_id,
                'title' => $wo->title,
                'start' => $wo->due_date?->toIso8601String() ?? $wo->requested_date->toIso8601String(),
                'end' => $wo->completion_time?->toIso8601String(),
                'allDay' => false,
                'backgroundColor' => $color,
                'borderColor' => $color,
                'editable' => false, // WOs are not drag-droppable
                'extendedProps' => [
                    'type' => 'wo',
                    'wo_id' => $wo->wo_id,
                    'asset_name' => $wo->asset->name ?? null,
                    'status' => $wo->status,
                    'priority' => $wo->priority,
                    'assigned_to' => $wo->assignedTo->full_name ?? 'Unassigned',
                    'is_overdue' => $isOverdue,
                ],
            ];
        })->toArray();
    }
}
