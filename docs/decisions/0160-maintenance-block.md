# 0160: Preventive maintenance is one block that opens dispatch work orders

- Status: accepted
- Date: 2026-10-31

## Context

Equipment needs work on a schedule: every 30 days, or every 500 hours run.
`dispatch` already owns work orders with technicians and spare parts,
`assets` owns the equipment, and `inventory` owns stock. Nothing decides when
a work order is due, and nothing keeps meter readings or calibration records
(ISO 9001 clause 7.1.5 asks for calibrated measuring equipment).

## Decision

`maintenance` is a block (`better-supabase/blocks/maintenance`) with five
tables: `maintenance_plans`, `maintenance_plan_parts`, `maintenance_meters`,
`maintenance_meter_readings` and `maintenance_calibrations`. Every table is
adoptable (ADR 0098). The block requires `dispatch`.

- A plan is a subject (`maintenance_plan`) with a kind. A `time` plan falls
  due `every_days` days after the last completion, or after it was created. A
  `meter` plan falls due when its meter's reading is `every_value` units above
  the reading at the last completion.
- A plan carries its spare parts. Generating a work order calls
  `dispatch.create_work_order` and `dispatch.record_work_order_part` for each
  part, so the stock block's variants and the dispatch part list stay the one
  source.
- `generate_maintenance_work_orders` opens one work order per due plan that has
  none open and returns the pairs. It is granted to the service role so a
  schedule can call it.
- A trigger on the dispatch work orders table closes the loop. A work order
  that reaches `done` sets the plan's last done date and reading and moves the
  next due date. A cancelled one frees the plan to open another.
- A reading never goes below the meter's latest one. A reading with an older
  `read_at` stays in the history only.
- A calibration records the instrument, the asset, the result (`pass`, `fail`,
  `adjusted`) and when it is due again. Overdue calibrations are read through
  `list_calibrations` with `dueBefore`.
- Permissions are `maintenance.read`, `maintenance.record` (readings and
  calibrations) and `maintenance.manage` (plans and meters), per ADR 0130.
- Events are `maintenance_plan.created`, `.updated`, `.deleted`, `.triggered`
  and `.completed`, `maintenance_meter_reading.recorded` and
  `maintenance_calibration.recorded`.

## Alternatives considered

- **Store plans on `assets`.** An asset has no schedule, and a plan can cover
  a group of equipment or none.
- **A separate work order table.** `dispatch` already assigns technicians and
  tracks status and parts.
- **Recurrence rules (RRULE) for time plans.** A fixed number of days covers
  the routine cases. Calendar-aligned schedules are deferred.

## Consequences

- A plan's work order is only generated when something calls the function.
  Apps schedule it, for example with a Vercel cron or the `jobs` block.
- Creating a work order needs the dispatch permission of the caller, so a user
  with only `maintenance.manage` can't generate work orders.
- Linking a plan to the `qualifications` of the technician who may do it is
  deferred.
