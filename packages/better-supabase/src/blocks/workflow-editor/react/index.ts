"use client";

import { useMemo } from "react";

import type {
  WorkflowEditorActions,
  WorkflowEditorSnapshot,
  WorkflowCanvasRunActions,
  WorkflowCanvasRunSnapshot,
} from "../client.ts";
import type { WorkflowEditor } from "../workflow-editor.ts";

import { rpcTransport } from "../../../core/block-transport.ts";
import { useController } from "../../react-controller.ts";
import { useBlockEnv } from "../../react-env.ts";
import { createWorkflows } from "../../workflows/workflows.ts";
import {
  createWorkflowEditorController,
  createWorkflowCanvasRunController,
} from "../client.ts";
import { createWorkflowEditor } from "../workflow-editor.ts";

export interface UseWorkflowEditorOptions {
  /** The tenant whose definitions to list. */
  readonly tenant?: string | null;
  /** The schema the calls go to (default `better_supabase`). */
  readonly schema?: string;
}

export interface WorkflowEditorState
  extends WorkflowEditorSnapshot, WorkflowEditorActions {
  /** The builder for the signed-in user, for saves, publishes and runs. */
  readonly builder: WorkflowEditor;
}

/**
 * The definitions the signed-in user may read and the step library, with a
 * builder bound to the user's session.
 *
 * ```tsx
 * const { definitions, steps, builder } = useWorkflowEditor({ tenant });
 * ```
 */
export function useWorkflowEditor(
  options: UseWorkflowEditorOptions = {},
): WorkflowEditorState {
  const { supabase, auth } = useBlockEnv();
  const { tenant, schema } = options;

  const builder = useMemo(
    () =>
      createWorkflowEditor({
        transport: rpcTransport(supabase),
        ...(schema === undefined ? {} : { schema }),
      }),
    [supabase, schema],
  );

  const { view } = useController(
    () =>
      createWorkflowEditorController({
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
 * A run and the status of each of its nodes, loaded again on each message on
 * `workflow-run:<id>` (run status changes and node records).
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
    const builder = createWorkflowEditor({ transport, ...scoped });

    return createWorkflowCanvasRunController({
      client: { runs: workflows.runs, nodeRuns: builder.nodeRuns },
      auth,
      ports,
      run,
    });
  }, [supabase, auth, ports, schema, run]).view;
}
