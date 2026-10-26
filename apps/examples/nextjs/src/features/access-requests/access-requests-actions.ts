"use server";

import { ok } from "better-supabase";
import { refresh } from "next/cache";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { refreshCaller } from "@/lib/refresh-caller";
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
    requireOrganization: true,
    authorize: async () =>
      can(await getPermissions(), "access_requests.create"),
  },
  async ({ role, duration, reason }, { tenant, db, auth }) => {
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

    refreshCaller(auth);

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
    requireOrganization: true,
    authorize: async () => can(await getPermissions(), "members.update_role"),
  },
  async ({ approvalId, decision }, { db, auth }) => {
    const { approvals } = db;

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
export const cancelAccessRequest = bsb.action(
  { input: v.object({ approvalId: ID }), requireOrganization: true },
  async ({ approvalId }, { db, auth }) => {
    const cancelled = await db.approvals.cancel(approvalId);

    if (!cancelled.ok) {
      return cancelled;
    }

    refreshCaller(auth);

    return ok(cancelled.data.id);
  },
);

/** Ends a granted role early: a manager, or the holder giving it up. */
export const endAccess = bsb.action(
  { input: v.object({ id: ID }), requireOrganization: true },
  async ({ id }, { db, auth }) => {
    const ended = await db.accessRequests.end(id);

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
