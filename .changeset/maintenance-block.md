---
"better-supabase": minor
---

New `maintenance` block (`better-supabase/blocks/maintenance`): preventive maintenance plans by time or meter that open dispatch work orders with their spare parts, meter readings and calibrations.

- `createPlan` takes a `time` plan (`everyDays`) or a `meter` plan (`meterId` and `everyValue`) with an optional asset, priority and spare parts. `updatePlan` pauses or changes it and `deletePlan` removes it.
- `generateWorkOrders` opens a dispatch work order, with the plan's parts, for every due plan that has none open. A work order that is done moves the plan's next due date, and a cancelled one frees the plan.
- `createMeter` and `recordReading` keep meters such as hours run. A reading never goes below the previous one.
- `recordCalibration` and `listCalibrations` keep calibration records with their due dates.
- The permission keys are `maintenance.read`, `maintenance.record` and `maintenance.manage`.

Add `maintenance: {}` to `blocks` next to `dispatch`, run `better-supabase add maintenance` and generate a migration. Call `generateWorkOrders` on a schedule.
