"use server";

import { dbError, err, ok, type RequestContext } from "better-supabase";
import {
  authorizeHook,
  HookForbiddenError,
  hookMetadata,
  startFor,
  workflowContext,
} from "better-supabase/workflow-sdk";
import { refresh } from "next/cache";
import * as v from "valibot";
import { getRun, resumeHook } from "workflow/api";

import {
  can,
  type Permission,
  PERMISSIONS,
} from "@/features/user/user-permissions";
import { blocks } from "@/lib/blocks";
import { bs } from "@/lib/supabase/server";

import {
  approvalToken,
  documentIngestion,
  expenseApproval,
  onboardingDrip,
} from "./workflow-definitions";

const WorkflowName = v.picklist(["onboarding-drip", "document-ingestion"]);

const isPermission = (value: string): value is Permission =>
  PERMISSIONS.some((permission) => permission === value);

function contextOf(userId: string, tenant: string): RequestContext {
  return { actor: { id: userId, kind: "user" }, tenant };
}

/** Starts a sample workflow as the caller in the active organization. */
export const startWorkflow = bs.action(
  {
    input: v.object({
      workflow: WorkflowName,
      text: v.optional(v.pipe(v.string(), v.maxLength(20_000))),
    }),
    requireTenant: true,
    authorize: (session) => can(session, "workflow.run"),
  },
  async ({ workflow, text }, { tenant, auth }) => {
    if (auth.kind !== "user") {
      return err(dbError("unauthorized", "Sign in to start a workflow"));
    }
    const context = contextOf(auth.user.id, tenant);
    const run =
      workflow === "onboarding-drip"
        ? await startFor(context, onboardingDrip, [workflowContext(context)])
        : await startFor(context, documentIngestion, [
            workflowContext(context),
            text ?? "",
          ]);
    refresh();
    return ok(run.runId);
  },
);

/** Starts an expense approval that the requester or an admin can decide. */
export const requestApproval = bs.action(
  {
    input: v.object({ amount: v.pipe(v.number(), v.minValue(1)) }),
    requireTenant: true,
    authorize: (session) => can(session, "workflow.run"),
  },
  async ({ amount }, { tenant, auth }) => {
    if (auth.kind !== "user") {
      return err(dbError("unauthorized", "Sign in to start a workflow"));
    }
    const context = contextOf(auth.user.id, tenant);
    const run = await startFor(context, expenseApproval, [
      workflowContext(context),
      amount,
      hookMetadata(context, "workflow.admin"),
    ]);
    refresh();
    return ok(run.runId);
  },
);

/**
 * Approves or rejects an expense approval run. `authorizeHook` checks the
 * hook's metadata against the caller, so knowing the token is not enough.
 */
export const decideApproval = bs.action(
  {
    input: v.object({ run: v.string(), approved: v.boolean() }),
    requireTenant: true,
  },
  async ({ run, approved }, { tenant, auth, session }) => {
    if (auth.kind !== "user") {
      return err(dbError("unauthorized", "Sign in to decide"));
    }
    try {
      const hook = await authorizeHook(
        approvalToken(run),
        contextOf(auth.user.id, tenant),
        {
          can: (hookTenant, permission) =>
            hookTenant === tenant &&
            isPermission(permission) &&
            can(session, permission),
        },
      );
      await resumeHook(hook, { approved, by: auth.user.id });
    } catch (error) {
      if (error instanceof HookForbiddenError) {
        return err(dbError("forbidden", "You may not decide this approval"));
      }
      throw error;
    }
    refresh();
    return ok(true);
  },
);

/** Marks the run cancelled in the registry, then cancels it in the engine. */
export const cancelRun = bs.action(
  { input: v.object({ run: v.string() }), requireTenant: true },
  async ({ run }, { supabase }) => {
    const marked = await blocks(supabase).workflows.runs.requestCancel(run);
    if (!marked.ok) return marked;
    if (marked.data === undefined) {
      return err(dbError("not_found", "No such run"));
    }
    await getRun(marked.data.externalId).cancel();
    refresh();
    return ok(true);
  },
);

/** Creates or replaces a schedule that starts a sample workflow as its creator. */
export const createSchedule = bs.action(
  {
    input: v.object({
      name: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(100)),
      workflow: WorkflowName,
      cron: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(100)),
    }),
    requireTenant: true,
    authorize: (session) => can(session, "workflow.admin"),
  },
  async ({ name, workflow, cron }, { tenant, auth, supabase }) => {
    if (auth.kind !== "user") {
      return err(dbError("unauthorized", "Sign in to schedule"));
    }
    const context = workflowContext(contextOf(auth.user.id, tenant));
    const created = await blocks(supabase).workflows.schedules.create({
      name,
      workflow,
      cron,
      tenant,
      // The argument list `workflowStarter` passes to the workflow.
      input:
        workflow === "onboarding-drip"
          ? [context]
          : [context, "A scheduled document."],
    });
    if (!created.ok) return created;
    refresh();
    return ok(created.data.id);
  },
);

export const pauseSchedule = bs.action(
  {
    input: v.object({ id: v.string(), paused: v.boolean() }),
    requireTenant: true,
  },
  async ({ id, paused }, { supabase }) => {
    const updated = await blocks(supabase).workflows.schedules.pause(
      id,
      paused,
    );
    if (!updated.ok) return updated;
    refresh();
    return ok(updated.data);
  },
);

export const removeSchedule = bs.action(
  { input: v.object({ id: v.string() }), requireTenant: true },
  async ({ id }, { supabase }) => {
    const removed = await blocks(supabase).workflows.schedules.remove(id);
    if (!removed.ok) return removed;
    refresh();
    return ok(removed.data);
  },
);
