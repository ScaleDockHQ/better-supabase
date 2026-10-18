"use server";

import { ok } from "better-supabase";
import { refresh } from "next/cache";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

import { can } from "@/features/user/user-permissions";
import { blocks } from "@/lib/blocks";
import { refreshCaller } from "@/lib/refresh-caller";
import { bs } from "@/lib/supabase/server";

const DURATIONS = ["PT1H", "P1D", "P7D", "none"] as const;

const ID = v.pipe(v.string(), v.uuid());

/** Asks the approvers for a role in the active organization. */
interface AccessRequestDraft {
  organizationId: string;
  role: string;
  reason?: string;
  duration?: Temporal.Duration;
}

export const requestAccess = bs.action(
  {
    input: v.object({
      role: v.picklist(["member", "admin"]),
      duration: v.picklist(DURATIONS),
      reason: v.optional(v.pipe(v.string(), v.trim(), v.maxLength(500))),
    }),
    requireTenant: true,
    authorize: (session) => can(session, "access_requests.create"),
  },
  async ({ role, duration, reason }, { tenant, supabase, auth }) => {
    const input: AccessRequestDraft = { organizationId: tenant, role };

    if (reason) {
      input.reason = reason;
    }

    if (duration !== "none") {
      input.duration = Temporal.Duration.from(duration);
    }

    const requested = await blocks(supabase).accessRequests.request(input);

    if (!requested.ok) {
      return requested;
    }

    refreshCaller(auth);

    return ok(requested.data.id);
  },
);

/** Approves or rejects the approvals request behind an access request. */
export const decideAccessRequest = bs.action(
  {
    input: v.object({
      approvalId: ID,
      decision: v.picklist(["approve", "reject"]),
    }),
    requireTenant: true,
    authorize: (session) => can(session, "members.update_role"),
  },
  async ({ approvalId, decision }, { supabase, auth }) => {
    const { approvals } = blocks(supabase);

    const decided =
      decision === "approve"
        ? await approvals.approve(approvalId)
        : await approvals.reject(approvalId);

    if (!decided.ok) {
      return decided;
    }

    refreshCaller(auth);

    return ok(decided.data.id);
  },
);

/** Withdraws the caller's own pending request. */
export const cancelAccessRequest = bs.action(
  {
    input: v.object({ approvalId: ID }),
    requireTenant: true,
  },
  async ({ approvalId }, { supabase, auth }) => {
    const cancelled = await blocks(supabase).approvals.cancel(approvalId);

    if (!cancelled.ok) {
      return cancelled;
    }

    refreshCaller(auth);

    return ok(cancelled.data.id);
  },
);

/** Ends a granted role early: a manager, or the holder giving it up. */
export const endAccess = bs.action(
  {
    input: v.object({ id: ID }),
    requireTenant: true,
  },
  async ({ id }, { supabase, auth }) => {
    const ended = await blocks(supabase).accessRequests.end(id);

    if (!ended.ok) {
      return ended;
    }

    refreshCaller(auth);

    return ok(ended.data.id);
  },
);

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
export async function refreshAccessRequests() {
  refresh();
}
