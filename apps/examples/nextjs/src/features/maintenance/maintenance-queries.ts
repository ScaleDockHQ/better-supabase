import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import { getAllPages } from "@/lib/read-all-pages";
import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

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

export function stateOf(plan: {
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
export async function getPlans(): Promise<readonly PlanRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(tags.maintenance());

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

export async function getPlan(id: string): Promise<PlanRow | null | undefined> {
  const plans = await getPlans();

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

export async function getMeters(): Promise<readonly MeterRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(tags.maintenance());

  if (!tenantOf(session)) {
    return null;
  }

  const meters = await getAllPages((page) => db.maintenance.meterPage(page));

  return meters.map((meter) => ({
    id: meter.id,
    name: meter.name,
    unit: meter.unit,
    reading: meter.reading,
    readAt: meter.readAt?.toString() ?? null,
    assetId: meter.assetId ?? null,
  }));
}
