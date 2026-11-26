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
import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

const TAGS = [tags.maintenance()];

const Priority = v.picklist(["low", "normal", "high", "urgent"]);

/** Opens a dispatch work order for every plan that is due. */
export const generateWorkOrders = bsb.action(
  {
    input: v.object({}),
    requireTenant: true,
    permission: "maintenance.manage",
    tags: () => TAGS,
    refresh: true,
  },
  async (_input, { db }) => {
    const opened = await db.maintenance.generateWorkOrders();

    if (!opened.ok) {
      return opened;
    }

    return ok({ opened: opened.data.length });
  },
);

/**
 * Creates a plan. A time plan repeats every N days, a meter plan every N units
 * of a meter, and a calendar plan follows an RRULE from its first date.
 */
export const createPlan = bsb.blockAction(
  ({ db }) => db.maintenance,
  "createPlan",
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
    tags: () => TAGS,
    refresh: true,
    args: (input) => [
      {
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
      },
    ],
  },
  (created) => ({ id: created.id }),
);

/** Pauses an active plan or resumes a paused one. */
export const setPlanStatus = bsb.blockAction(
  ({ db }) => db.maintenance,
  "updatePlan",
  {
    input: v.object({ planId: Id, status: v.picklist(["active", "paused"]) }),
    requireTenant: true,
    permission: "maintenance.manage",
    tags: () => TAGS,
    refresh: true,
    args: ({ planId, status }) => [{ planId, change: { status } }],
  },
  () => true,
);

export const changePlanPriority = bsb.blockAction(
  ({ db }) => db.maintenance,
  "updatePlan",
  {
    input: v.object({ planId: Id, priority: Priority }),
    requireTenant: true,
    permission: "maintenance.manage",
    tags: () => TAGS,
    refresh: true,
    args: ({ planId, priority }) => [{ planId, change: { priority } }],
  },
  () => true,
);

export const deletePlan = bsb.blockAction(
  ({ db }) => db.maintenance,
  "purgePlan",
  {
    input: v.object({ planId: Id }),
    requireTenant: true,
    permission: "maintenance.manage",
    tags: () => TAGS,
    refresh: true,
    args: ({ planId }) => [planId],
  },
  () => true,
);

export const createMeter = bsb.blockAction(
  ({ db }) => db.maintenance,
  "createMeter",
  {
    input: v.object({
      name: Name,
      unit: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(20)),
    }),
    requireTenant: true,
    permission: "maintenance.manage",
    tags: () => TAGS,
    refresh: true,
  },
  (created) => ({ id: created.id }),
);

/** A meter reading never goes below the last one. */
export const recordReading = bsb.blockAction(
  ({ db }) => db.maintenance,
  "recordReading",
  {
    input: v.object({ meterId: Id, value: Decimal }),
    requireTenant: true,
    permission: "maintenance.record",
    tags: () => TAGS,
    refresh: true,
  },
  () => true,
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
    tags: () => TAGS,
    refresh: true,
  },
  async (input, { db }) => {
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

    return ok({ id: saved.data.id });
  },
);
