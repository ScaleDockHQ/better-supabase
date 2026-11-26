"use server";

import type { LeaveRequestInput } from "better-supabase/blocks/leave";

import { ok } from "better-supabase";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

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
    tags: () => [tags.leave()],
    refresh: true,
  },
  async (input, { tenant, db }) => {
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

    return ok({ id: requested.data.id, amount: requested.data.amount });
  },
);

/** Cancels a pending request, or approved leave before it starts. */
export const cancelLeave = bsb.blockAction(
  ({ db }) => db.leave,
  "cancel",
  {
    input: v.object({ requestId: Id }),
    requireTenant: true,
    permission: "leave.request",
    tags: () => [tags.leave()],
    refresh: true,
    args: ({ requestId }) => [requestId],
  },
  (cancelled) => ({ status: cancelled.status }),
);

/** Approves or rejects a request through its approval. */
export const decideLeave = bsb.action(
  {
    input: v.object({ approvalId: Id, approved: v.boolean(), comment: Note }),
    requireTenant: true,
    permission: "leave.approve",
    tags: () => [tags.leave()],
    refresh: true,
  },
  async ({ approvalId, approved, comment }, { db }) => {
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

    return ok({ status: decided.data.status });
  },
);

/** Creates the types a new organization starts with. */
export const setUpLeaveTypes = bsb.action(
  {
    input: v.object({}),
    requireTenant: true,
    permission: "leave.manage",
    tags: () => [tags.leave()],
    refresh: true,
  },
  async (_input, { tenant, db }) => {
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

    return ok({ granted: accrued.data });
  },
);
