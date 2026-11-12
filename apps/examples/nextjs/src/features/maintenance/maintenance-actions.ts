"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import {
  Decimal,
  Id,
  instantOf,
  given,
  Name,
  Optional,
  Whole,
} from "@/lib/form-input";
import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { MAINTENANCE_TAG } from "./maintenance-cache";

const TAGS = [MAINTENANCE_TAG];

const Priority = v.picklist(["low", "normal", "high", "urgent"]);

/** Opens a dispatch work order for every plan that is due. */
export const generateWorkOrders = bsb.action(
  {
    input: v.object({}),
    requireTenant: true,
    permission: "maintenance.manage",
  },
  async (_input, { db, auth }) => {
    const opened = await db.maintenance.generateWorkOrders();

    if (!opened.ok) {
      return opened;
    }

    await refreshCaller(auth, TAGS);

    return ok({ opened: opened.data.length });
  },
);

/**
 * Creates a plan. A time plan repeats every N days, a meter plan every N units
 * of a meter, and a calendar plan follows an RRULE from its first date.
 */
export const createPlan = bsb.action(
  {
    input: v.object({
      title: Name,
      kind: v.picklist(["time", "meter", "rrule"]),
      priority: Priority,
      everyDays: Optional,
      meterId: Optional,
      everyValue: Optional,
      rrule: Optional,
      startsOn: Optional,
    }),
    requireTenant: true,
    permission: "maintenance.manage",
  },
  async (input, { db, auth }) => {
    const created = await db.maintenance.createPlan({
      title: input.title,
      kind: input.kind,
      priority: input.priority,
      ...given(
        "everyDays",
        input.kind === "time" ? Number(input.everyDays ?? "30") : undefined,
      ),
      ...given("meterId", input.kind === "meter" ? input.meterId : undefined),
      ...given(
        "everyValue",
        input.kind === "meter" ? input.everyValue : undefined,
      ),
      ...given(
        "rrule",
        input.kind === "rrule" ? (input.rrule ?? "FREQ=MONTHLY") : undefined,
      ),
      ...given(
        "dtstart",
        input.kind === "rrule"
          ? (instantOf(input.startsOn) ??
              instantOf(new Date().toISOString().slice(0, 10)))
          : undefined,
      ),
    });

    if (!created.ok) {
      return created;
    }

    await refreshCaller(auth, TAGS);

    return ok({ id: created.data.id });
  },
);

/** Pauses an active plan or resumes a paused one. */
export const setPlanStatus = bsb.action(
  {
    input: v.object({ planId: Id, status: v.picklist(["active", "paused"]) }),
    requireTenant: true,
    permission: "maintenance.manage",
  },
  async ({ planId, status }, { db, auth }) => {
    const saved = await db.maintenance.updatePlan({
      planId,
      change: { status },
    });

    if (!saved.ok) {
      return saved;
    }

    await refreshCaller(auth, TAGS);

    return ok(true);
  },
);

export const changePlanPriority = bsb.action(
  {
    input: v.object({ planId: Id, priority: Priority }),
    requireTenant: true,
    permission: "maintenance.manage",
  },
  async ({ planId, priority }, { db, auth }) => {
    const saved = await db.maintenance.updatePlan({
      planId,
      change: { priority },
    });

    if (!saved.ok) {
      return saved;
    }

    await refreshCaller(auth, TAGS);

    return ok(true);
  },
);

export const deletePlan = bsb.action(
  {
    input: v.object({ planId: Id }),
    requireTenant: true,
    permission: "maintenance.manage",
  },
  async ({ planId }, { db, auth }) => {
    const removed = await db.maintenance.deletePlan(planId);

    if (!removed.ok) {
      return removed;
    }

    await refreshCaller(auth, TAGS);

    return ok(true);
  },
);

export const createMeter = bsb.action(
  {
    input: v.object({
      name: Name,
      unit: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(20)),
    }),
    requireTenant: true,
    permission: "maintenance.manage",
  },
  async ({ name, unit }, { db, auth }) => {
    const created = await db.maintenance.createMeter({ name, unit });

    if (!created.ok) {
      return created;
    }

    await refreshCaller(auth, TAGS);

    return ok({ id: created.data.id });
  },
);

/** A meter reading never goes below the last one. */
export const recordReading = bsb.action(
  {
    input: v.object({ meterId: Id, value: Decimal }),
    requireTenant: true,
    permission: "maintenance.record",
  },
  async ({ meterId, value }, { db, auth }) => {
    const saved = await db.maintenance.recordReading({ meterId, value });

    if (!saved.ok) {
      return saved;
    }

    await refreshCaller(auth, TAGS);

    return ok(true);
  },
);

export const recordCalibration = bsb.action(
  {
    input: v.object({
      instrument: Name,
      performedOn: Optional,
      everyDays: Whole(1, 3650),
      result: v.picklist(["pass", "fail", "adjusted"]),
      reference: Optional,
    }),
    requireTenant: true,
    permission: "maintenance.record",
  },
  async (input, { db, auth }) => {
    const performedAt = instantOf(
      input.performedOn ?? new Date().toISOString().slice(0, 10),
    );

    if (performedAt === undefined) {
      return ok(false);
    }

    const saved = await db.maintenance.recordCalibration({
      instrument: input.instrument,
      performedAt,
      dueAt: performedAt.add({ hours: input.everyDays * 24 }),
      result: input.result,
      ...given("reference", input.reference),
    });

    if (!saved.ok) {
      return saved;
    }

    await refreshCaller(auth, TAGS);

    return ok({ id: saved.data.id });
  },
);
