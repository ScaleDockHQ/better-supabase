"use server";

import { ok } from "better-supabase";
import { refresh } from "next/cache";
import * as v from "valibot";

import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { APPROVAL_ACTIONS, APPROVAL_SUBJECT } from "./approvals-types";

const Id = v.pipe(v.string(), v.uuid());
const Comment = v.optional(v.pipe(v.string(), v.trim(), v.maxLength(500)), "");

/** Files a request under the customer policy for the action. */
export const requestApproval = bsb.action(
  {
    input: v.object({
      subjectId: Id,
      action: v.picklist(APPROVAL_ACTIONS),
      reason: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(500)),
    }),
    requireTenant: true,
    authorize: async () => can(await getPermissions(), "approvals.request"),
  },
  async ({ subjectId, action, reason }, { db, auth }) => {
    const requested = await db.approvals.request(
      { type: APPROVAL_SUBJECT, id: subjectId },
      { action, reason },
    );

    if (!requested.ok) {
      return requested;
    }

    refreshCaller(auth);

    return ok(requested.data.id);
  },
);

/**
 * Approves or rejects the request's current step. The block checks that the
 * caller is one of the step's approvers.
 */
export const decideApproval = bsb.action(
  {
    input: v.object({
      id: Id,
      decision: v.picklist(["approve", "reject"]),
      comment: Comment,
    }),
    requireTenant: true,
    authorize: async () => can(await getPermissions(), "approvals.read"),
  },
  async ({ id, decision, comment }, { db, auth }) => {
    const { approvals } = db;
    const note = comment === "" ? undefined : comment;

    const decided =
      decision === "approve"
        ? await approvals.approve(id, note)
        : await approvals.reject(id, note);

    if (!decided.ok) {
      return decided;
    }

    refreshCaller(auth);

    return ok(decided.data.status);
  },
);

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
export async function retryApprovals() {
  refresh();
}
