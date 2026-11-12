"use server";

import type { LeaveRequestInput } from "better-supabase/blocks/leave";

import { ok } from "better-supabase";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { LEAVE_TAG } from "./leave-cache";

interface ApprovalDecision {
  readonly id: string;
  readonly comment?: string;
}

type Writable<T> = { -readonly [K in keyof T]: T[K] };

const Id = v.pipe(v.string(), v.uuid());
const PlainDate = v.pipe(v.string(), v.isoDate());

const Note = v.optional(
  v.pipe(
    v.string(),
    v.trim(),
    v.maxLength(500),
    v.transform((value) => (value === "" ? undefined : value)),
  ),
);

/** Asks for leave; the request opens its approval. */
export const requestLeave = bsb.action(
  {
    input: v.object({
      typeId: Id,
      startsOn: PlainDate,
      endsOn: v.optional(v.union([v.literal(""), PlainDate]), ""),
      partial: v.optional(v.picklist(["full", "morning", "afternoon"]), "full"),
      note: Note,
    }),
    requireTenant: true,
    permission: "leave.request",
  },
  async (input, { tenant, db, auth }) => {
    const leave: Writable<LeaveRequestInput> = {
      typeId: input.typeId,
      startsOn: Temporal.PlainDate.from(input.startsOn),
    };

    if (input.endsOn !== "") {
      leave.endsOn = Temporal.PlainDate.from(input.endsOn);
    }

    if (input.partial !== "full") {
      leave.partial = input.partial;
    }

    if (input.note !== undefined) {
      leave.note = input.note;
    }

    const requested = await db.leave.request({
      organizationId: tenant,
      input: leave,
    });

    if (!requested.ok) {
      return requested;
    }

    await refreshCaller(auth, [LEAVE_TAG]);

    return ok({ id: requested.data.id, amount: requested.data.amount });
  },
);

/** Cancels a pending request, or approved leave before it starts. */
export const cancelLeave = bsb.action(
  {
    input: v.object({ requestId: Id }),
    requireTenant: true,
    permission: "leave.request",
  },
  async ({ requestId }, { db, auth }) => {
    const cancelled = await db.leave.cancel(requestId);

    if (!cancelled.ok) {
      return cancelled;
    }

    await refreshCaller(auth, [LEAVE_TAG]);

    return ok({ status: cancelled.data.status });
  },
);

/** Approves or rejects a request through its approval. */
export const decideLeave = bsb.action(
  {
    input: v.object({ approvalId: Id, approved: v.boolean(), comment: Note }),
    requireTenant: true,
    permission: "leave.approve",
  },
  async ({ approvalId, approved, comment }, { db, auth }) => {
    const input: Writable<ApprovalDecision> = { id: approvalId };

    if (comment !== undefined) {
      input.comment = comment;
    }

    const decided = approved
      ? await db.approvals.approve(input)
      : await db.approvals.reject(input);

    if (!decided.ok) {
      return decided;
    }

    await refreshCaller(auth, [LEAVE_TAG]);

    return ok({ status: decided.data.status });
  },
);

/** Creates the types a new organization starts with. */
export const setUpLeaveTypes = bsb.action(
  { input: v.object({}), requireTenant: true, permission: "leave.manage" },
  async (_input, { tenant, db, auth }) => {
    const vacation = await db.leave.saveType({
      organizationId: tenant,
      input: {
        key: "vacation",
        name: "Vacation",
        allowance: 25,
        carryoverMax: 5,
      },
    });

    if (!vacation.ok) {
      return vacation;
    }

    const sick = await db.leave.saveType({
      organizationId: tenant,
      input: {
        key: "sick",
        name: "Sick leave",
        tracked: false,
        autoApprove: true,
      },
    });

    if (!sick.ok) {
      return sick;
    }

    const accrued = await db.leave.accrue({
      organizationId: tenant,
      accrual: {
        typeId: vacation.data.id,
        period: Temporal.Now.plainDateISO().year,
        idempotencyKey: `vacation-${Temporal.Now.plainDateISO().year}`,
      },
    });

    if (!accrued.ok) {
      return accrued;
    }

    await refreshCaller(auth, [LEAVE_TAG]);

    return ok({ granted: accrued.data });
  },
);
