"use client";

import type {
  WorkflowRunActions,
  WorkflowRunsActions,
  WorkflowRunSnapshot,
  WorkflowRunsSnapshot,
} from "../client.ts";
import type { WorkflowRunStatus } from "../workflows.ts";

import { rpcTransport } from "../../../core/block-transport.ts";
import { useController } from "../../react-controller.ts";
import { useBlockEnv } from "../../react-env.ts";
import {
  createWorkflowRunController,
  createWorkflowRunsController,
} from "../client.ts";
import { createWorkflows } from "../workflows.ts";

export interface UseWorkflowRunsOptions {
  /**
   * The tenant whose runs to list; it also joins the tenant's
   * `workflow-runs:<tenant>` topic. Without one, the signed-in user's own runs
   * load once.
   */
  readonly tenant?: string | null;
  readonly definition?: string;
  readonly status?: WorkflowRunStatus;
  readonly limit?: number;
  /**
   * The schema the calls go to: the module schema (default `better_supabase`),
   * or the API schema from `blocks.workflows.api`.
   */
  readonly schema?: string;
}

export interface WorkflowRunsState
  extends WorkflowRunsSnapshot, WorkflowRunsActions {}

/**
 * The runs the signed-in user may read, newest first, loaded again when a run
 * in the tenant changes status.
 *
 * ```tsx
 * const { runs } = useWorkflowRuns({ tenant: organizationId });
 * ```
 */
export function useWorkflowRuns(
  options: UseWorkflowRunsOptions = {},
): WorkflowRunsState {
  const { supabase, auth, ports } = useBlockEnv();
  const { schema, tenant, definition, status, limit } = options;

  return useController(
    () =>
      createWorkflowRunsController({
        client: createWorkflows({
          transport: rpcTransport(supabase),
          ...(schema === undefined ? {} : { schema }),
        }),
        auth,
        ports,
        tenant: tenant ?? null,
        ...(definition === undefined ? {} : { definition }),
        ...(status === undefined ? {} : { status }),
        ...(limit === undefined ? {} : { limit }),
      }),
    [supabase, auth, ports, schema, tenant, definition, status, limit],
  ).view;
}

export interface UseWorkflowRunOptions {
  readonly schema?: string;
}

export interface WorkflowRunState
  extends WorkflowRunSnapshot, WorkflowRunActions {}

/**
 * One run by its id or its engine's id, loaded again on each status change
 * broadcast on `workflow-run:<id>`.
 */
export function useWorkflowRun(
  run: string | null,
  options: UseWorkflowRunOptions = {},
): WorkflowRunState {
  const { supabase, auth, ports } = useBlockEnv();
  const { schema } = options;

  return useController(
    () =>
      createWorkflowRunController({
        client: createWorkflows({
          transport: rpcTransport(supabase),
          ...(schema === undefined ? {} : { schema }),
        }),
        auth,
        ports,
        run,
      }),
    [supabase, auth, ports, schema, run],
  ).view;
}
