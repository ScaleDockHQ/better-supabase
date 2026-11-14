"use server";

import { err, invalidInput, ok } from "better-supabase";
import { revalidatePath } from "next/cache";
import * as v from "valibot";

import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { SUPPORT_TAG } from "./support-cache";

const Id = v.pipe(v.string(), v.uuid());

/**
 * Asks for a read-only support session on a user. A second platform admin
 * approves it before the session can start.
 */
export const requestSupportSession = bsb.action(
  {
    input: v.object({
      target: Id,
      reason: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(500)),
    }),
    permission: "impersonation.start",
  },
  async ({ target, reason }, { db, auth }) => {
    const result = await db.impersonation.request({
      target,
      reason,
      readOnly: true,
    });

    if (!result.ok) {
      return err(result.error);
    }

    await refreshCaller(auth, [SUPPORT_TAG]);

    return ok(target);
  },
);

/** Ends a support session before it expires. */
export const endSupportSession = bsb.action(
  { input: v.object({ sessionId: Id }), permission: "impersonation.revoke" },
  async ({ sessionId }, { db, auth }) => {
    const result = await db.impersonation.end(sessionId);

    if (!result.ok) {
      return err(result.error);
    }

    await refreshCaller(auth, [SUPPORT_TAG]);

    return ok(sessionId);
  },
);

const ViewAs = v.object({
  target: Id,
  reason: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(500)),
});

/** What `viewAsMember` did: opened the session, or filed a request for approval. */
export type ViewAsOutcome = "started" | "requested";

/**
 * Views the app as a member from the members page. A session starts when a
 * second platform admin already approved a request for this member; otherwise
 * the action files the request and the admin starts the session after the
 * approval on /approvals. The database checks the platform permission both
 * ways.
 */
export async function viewAsMember(input: {
  readonly target: string;
  readonly reason: string;
}) {
  const parsed = v.safeParse(ViewAs, input);

  if (!parsed.success) {
    return err(invalidInput("Name the member and the reason.", []));
  }

  const { target, reason } = parsed.output;

  const started = await bsb.startSupport({ targetUserId: target, reason });

  if (started.ok) {
    revalidatePath("/", "layout");

    return ok<ViewAsOutcome>("started");
  }

  if (started.error.code !== "IMPERSONATION_APPROVAL_REQUIRED") {
    return err(started.error);
  }

  const { db, auth } = await bsb.context();

  const requested = await db.impersonation.request({
    target,
    reason,
    readOnly: true,
  });

  if (!requested.ok) {
    return err(requested.error);
  }

  await refreshCaller(auth, [SUPPORT_TAG]);

  return ok<ViewAsOutcome>("requested");
}

/**
 * Leaves the support session: the server ends it in the database (the module
 * records the end in the audit log and emits `support_session.ended`) and
 * clears the cookie, so the admin sees their own view again.
 */
export async function exitSupportSession() {
  const stopped = await bsb.stopSupport();

  if (!stopped.ok) {
    return err(stopped.error);
  }

  revalidatePath("/", "layout");

  return ok(stopped.data.ended);
}
