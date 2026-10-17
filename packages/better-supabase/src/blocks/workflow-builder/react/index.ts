"use client";

import { useMemo } from "react";

import type {
  WorkflowBuilderActions,
  WorkflowBuilderSnapshot,
  WorkflowCanvasRunActions,
  WorkflowCanvasRunSnapshot,
} from "../client.ts";
import type { WorkflowBuilder } from "../workflow-builder.ts";

import { rpcTransport } from "../../../core/block-transport.ts";
import { useController } from "../../react-controller.ts";
import { useBlockEnv } from "../../react-env.ts";
import { createWorkflows } from "../../workflows/workflows.ts";
import {
  createWorkflowBuilderController,
  createWorkflowCanvasRunController,
} from "../client.ts";
import { createWorkflowBuilder } from "../workflow-builder.ts";

export interface UseWorkflowBuilderOptions {
  /** The tenant whose definitions to list. */
  readonly tenant?: string | null;
  /** The schema the calls go to (default `better_supabase`). */
  readonly schema?: string;
}

export interface WorkflowBuilderState
  extends WorkflowBuilderSnapshot, WorkflowBuilderActions {
  /** The builder for the signed-in user, for saves, publishes and runs. */
  readonly builder: WorkflowBuilder;
}

/**
 * The definitions the signed-in user may read and the step library, with a
 * builder bound to the user's session.
 *
 * ```tsx
 * const { definitions, steps, builder } = useWorkflowBuilder({ tenant });
 * ```
 */
export function useWorkflowBuilder(
  options: UseWorkflowBuilderOptions = {},
): WorkflowBuilderState {
  const { supabase, auth } = useBlockEnv();
  const { tenant, schema } = options;

  const builder = useMemo(
    () =>
      createWorkflowBuilder({
        transport: rpcTransport(supabase),
        ...(schema === undefined ? {} : { schema }),
      }),
    [supabase, schema],
  );

  const { view } = useController(
    () =>
      createWorkflowBuilderController({
        client: builder,
        auth,
        tenant: tenant ?? null,
      }),
    [builder, auth, tenant],
  );

  return useMemo(() => ({ ...view, builder }), [view, builder]);
}

export interface UseWorkflowCanvasRunOptions {
  readonly schema?: string;
}

export interface WorkflowCanvasRunState
  extends WorkflowCanvasRunSnapshot, WorkflowCanvasRunActions {}

/**
 * A run and the status of each of its nodes, loaded again on each message
 * on `workflow-run:<id>` (run status changes and node records).
 */
export function useWorkflowCanvasRun(
  run: string | null,
  options: UseWorkflowCanvasRunOptions = {},
): WorkflowCanvasRunState {
  const { supabase, auth, ports } = useBlockEnv();
  const { schema } = options;

  return useController(() => {
    const transport = rpcTransport(supabase);
    const scoped = schema === undefined ? {} : { schema };
    const workflows = createWorkflows({ transport, ...scoped });
    const builder = createWorkflowBuilder({ transport, ...scoped });

    return createWorkflowCanvasRunController({
      client: { runs: workflows.runs, nodeRuns: builder.nodeRuns },
      auth,
      ports,
      run,
    });
  }, [supabase, auth, ports, schema, run]).view;
}
