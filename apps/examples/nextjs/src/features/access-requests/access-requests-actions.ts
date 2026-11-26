"use server";

import { ok } from "better-supabase";
import { refresh } from "next/cache";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

const DURATIONS = ["PT1H", "P1D", "P7D", "none"] as const;

const ID = v.pipe(v.string(), v.uuid());

/** Asks the approvers for a role in the active organization. */
interface AccessRequestDraft {
  organizationId: string;
  role: string;
  reason?: string;
  duration?: Temporal.Duration;
}

export const requestAccess = bsb.action(
  {
    input: v.object({
      role: v.picklist(["member", "admin"]),
      duration: v.picklist(DURATIONS),
      reason: v.optional(v.pipe(v.string(), v.trim(), v.maxLength(500))),
    }),
    requireTenant: true,
    permission: "access_requests.create",
    tags: () => [tags.accessRequests(), tags.approvals()],
    refresh: true,
  },
  async ({ role, duration, reason }, { tenant, db }) => {
    const input: AccessRequestDraft = { organizationId: tenant, role };

    if (reason) {
      input.reason = reason;
    }

    if (duration !== "none") {
      input.duration = Temporal.Duration.from(duration);
    }

    const requested = await db.accessRequests.request(input);

    if (!requested.ok) {
      return requested;
    }

    return ok(requested.data.id);
  },
);

/** Approves or rejects the approvals request behind an access request. */
export const decideAccessRequest = bsb.action(
  {
    input: v.object({
      approvalId: ID,
      decision: v.picklist(["approve", "reject"]),
    }),
    requireTenant: true,
    permission: "members.update_role",
    tags: () => [tags.accessRequests(), tags.approvals()],
    refresh: true,
  },
  async ({ approvalId, decision }, { db }) => {
    const { approvals } = db;

    const decided =
      decision === "approve"
        ? await approvals.approve({ id: approvalId })
        : await approvals.reject({ id: approvalId });

    if (!decided.ok) {
      return decided;
    }

    return ok(decided.data.id);
  },
);

/** Withdraws the caller's own pending request. */
export const cancelAccessRequest = bsb.blockAction(
  ({ db }) => db.approvals,
  "cancel",
  {
    input: v.object({ approvalId: ID }),
    requireTenant: true,
    tags: () => [tags.accessRequests(), tags.approvals()],
    refresh: true,
    args: ({ approvalId }) => [approvalId],
  },
  (cancelled) => cancelled.id,
);

/** Ends a granted role early: a manager, or the holder giving it up. */
export const endAccess = bsb.blockAction(
  ({ db }) => db.accessRequests,
  "end",
  {
    input: v.object({ id: ID }),
    requireTenant: true,
    tags: () => [tags.accessRequests(), tags.approvals()],
    refresh: true,
    args: ({ id }) => [id],
  },
  (ended) => ended.id,
);

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
export async function refreshAccessRequests() {
  refresh();
}
