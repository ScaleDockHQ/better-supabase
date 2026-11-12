import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import { bsb } from "@/lib/supabase/server";

import { MAINTENANCE_TAG } from "./maintenance-cache";

export type MaintenanceKind = "time" | "meter" | "rrule";

export type MaintenancePriority = "low" | "normal" | "high" | "urgent";

/** What a plan is doing right now, for the status facet. */
export type PlanState = "paused" | "work_order" | "due" | "scheduled";

export interface PlanPart {
  readonly id: string;
  readonly name: string;
  readonly quantity: string;
}

/** A maintenance plan as the overview and the detail page show it. */
export interface PlanRow {
  readonly id: string;
  readonly title: string;
  readonly kind: MaintenanceKind;
  readonly priority: MaintenancePriority;
  readonly state: PlanState;
  readonly everyDays: number | null;
  readonly everyValue: string | null;
  readonly rrule: string | null;
  readonly meterId: string | null;
  readonly assetId: string | null;
  readonly nextDueAt: string | null;
  readonly lastDoneAt: string | null;
  readonly workOrderId: string | null;
  readonly parts: readonly PlanPart[];
}

function stateOf(plan: {
  readonly status: "active" | "paused";
  readonly due: boolean;
  readonly workOrderId?: string | undefined;
}): PlanState {
  if (plan.status === "paused") {
    return "paused";
  }

  if (plan.workOrderId !== undefined) {
    return "work_order";
  }

  return plan.due ? "due" : "scheduled";
}

/**
 * The newest 200 plans, the soonest due first. The block has no text search or
 * `getPlan`, so the overview searches and pages these rows on the server and
 * the detail page finds its plan among them (EX-1100).
 */
export async function loadPlans(): Promise<readonly PlanRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(MAINTENANCE_TAG);

  if (!tenantOf(session)) {
    return null;
  }

  const plans = await db.maintenance.listPlans({ limit: 200 }).orThrow();

  return plans.map((plan) => ({
    id: plan.id,
    title: plan.title,
    kind: plan.kind,
    priority: plan.priority,
    state: stateOf(plan),
    everyDays: plan.everyDays ?? null,
    everyValue: plan.everyValue ?? null,
    rrule: plan.rrule ?? null,
    meterId: plan.meterId ?? null,
    assetId: plan.assetId ?? null,
    nextDueAt: plan.nextDueAt?.toString() ?? null,
    lastDoneAt: plan.lastDoneAt?.toString() ?? null,
    workOrderId: plan.workOrderId ?? null,
    parts: plan.parts.map((part) => ({
      id: part.id,
      name: part.name,
      quantity: part.quantity,
    })),
  }));
}

export async function loadPlan(
  id: string,
): Promise<PlanRow | null | undefined> {
  const plans = await loadPlans();

  return plans === null ? null : plans.find((plan) => plan.id === id);
}

export interface MeterRow {
  readonly id: string;
  readonly name: string;
  readonly unit: string;
  readonly reading: string;
  readonly readAt: string | null;
  readonly assetId: string | null;
}

export async function loadMeters(): Promise<readonly MeterRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(MAINTENANCE_TAG);

  if (!tenantOf(session)) {
    return null;
  }

  const meters = await db.maintenance.listMeters().orThrow();

  return meters.map((meter) => ({
    id: meter.id,
    name: meter.name,
    unit: meter.unit,
    reading: meter.reading,
    readAt: meter.readAt?.toString() ?? null,
    assetId: meter.assetId ?? null,
  }));
}

export interface CalibrationRow {
  readonly id: string;
  readonly instrument: string;
  readonly result: "pass" | "fail" | "adjusted";
  readonly performedAt: string;
  readonly dueAt: string;
  readonly reference: string | null;
  readonly overdue: boolean;
}

export async function loadCalibrations(): Promise<
  readonly CalibrationRow[] | null
> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(MAINTENANCE_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const calibrations = await db.maintenance
    .listCalibrations({ limit: 200 })
    .orThrow();

  const now = Date.now();

  return calibrations.map((row) => ({
    id: row.id,
    instrument: row.instrument,
    result: row.result,
    performedAt: row.performedAt.toString(),
    dueAt: row.dueAt.toString(),
    reference: row.reference ?? null,
    overdue: row.dueAt.epochMilliseconds < now,
  }));
}
