"use client";

import { useCallback, useEffect, useMemo, useState } from "react";

import type { DbError } from "../../../core/errors.ts";
import type { SubscriptionStatus } from "../../../realtime/index.ts";
import type { WorkflowRun } from "../../workflows/workflows.ts";
import type {
  WorkflowBuilder,
  WorkflowDefinition,
  WorkflowNodeRun,
  WorkflowStepInfo,
} from "../workflow-builder.ts";

import { rpcTransport } from "../../../core/block-transport.ts";
import { useAuth, useSupabase } from "../../../react/hooks.ts";
import { watchTopic } from "../../react-topic.ts";
import { createWorkflows } from "../../workflows/workflows.ts";
import { createBuilder } from "../workflow-builder.ts";

export interface UseWorkflowBuilderOptions {
  /** The tenant whose definitions to list. */
  readonly tenant?: string | null;
  /** The schema the calls go to (default `better_supabase`). */
  readonly schema?: string;
}

export interface WorkflowBuilderState {
  /** `undefined` until the first load. */
  readonly definitions: readonly WorkflowDefinition[] | undefined;
  /** The step library, the canvas's palette. */
  readonly steps: readonly WorkflowStepInfo[] | undefined;
  readonly error: DbError | undefined;
  readonly refresh: () => Promise<void>;
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
  const supabase = useSupabase();
  const auth = useAuth();
  const [definitions, setDefinitions] = useState<
    readonly WorkflowDefinition[] | undefined
  >(undefined);
  const [steps, setSteps] = useState<readonly WorkflowStepInfo[] | undefined>(
    undefined,
  );
  const [error, setError] = useState<DbError | undefined>(undefined);
  const tenant = options.tenant ?? null;
  const schema = options.schema;
  const builder = useMemo(
    () =>
      createBuilder({
        transport: rpcTransport(supabase),
        ...(schema === undefined ? {} : { schema }),
      }),
    [supabase, schema],
  );
  const userId = auth.user?.id ?? null;

  const refresh = useCallback(async () => {
    const [listed, library] = await Promise.all([
      builder.definitions.list(tenant ?? undefined),
      builder.steps.list(),
    ]);
    if (listed.ok) setDefinitions(listed.data);
    if (library.ok) setSteps(library.data);
    setError(
      listed.ok ? (library.ok ? undefined : library.error) : listed.error,
    );
  }, [builder, tenant]);

  useEffect(() => {
    if (auth.status !== "signed-in") return;
    // oxlint-disable-next-line react/set-state-in-effect -- refresh sets state only after the RPCs resolve.
    void refresh();
    // oxlint-disable-next-line react/exhaustive-effect-dependencies -- userId reloads for the new user.
  }, [userId, auth.status, refresh]);

  return { definitions, steps, error, refresh, builder };
}

export interface UseWorkflowCanvasRunOptions {
  readonly schema?: string;
}

export interface WorkflowCanvasRunState {
  readonly run: WorkflowRun | undefined;
  /** Each node's status by node id, for the canvas overlay. */
  readonly nodes: Readonly<Record<string, WorkflowNodeRun>>;
  readonly error: DbError | undefined;
  readonly status: SubscriptionStatus;
  readonly refresh: () => Promise<void>;
}

const NO_NODES: Readonly<Record<string, WorkflowNodeRun>> = {};

/**
 * A run and the status of each of its nodes, loaded again on each message
 * on `workflow-run:<id>` (run status changes and node records).
 */
export function useWorkflowCanvasRun(
  run: string | null,
  options: UseWorkflowCanvasRunOptions = {},
): WorkflowCanvasRunState {
  const supabase = useSupabase();
  const auth = useAuth();
  const [current, setCurrent] = useState<WorkflowRun | undefined>(undefined);
  const [nodes, setNodes] =
    useState<Readonly<Record<string, WorkflowNodeRun>>>(NO_NODES);
  const [error, setError] = useState<DbError | undefined>(undefined);
  const [status, setStatus] = useState<SubscriptionStatus>("closed");
  const schema = options.schema;
  const clients = useMemo(() => {
    const transport = rpcTransport(supabase);
    const scoped = schema === undefined ? {} : { schema };
    return {
      workflows: createWorkflows({ transport, ...scoped }),
      builder: createBuilder({ transport, ...scoped }),
    };
  }, [supabase, schema]);
  const userId = auth.user?.id ?? null;

  const refresh = useCallback(async () => {
    if (run === null) return;
    const [found, listed] = await Promise.all([
      clients.workflows.runs.get(run),
      clients.builder.nodeRuns.list(run),
    ]);
    if (found.ok) setCurrent(found.data);
    if (listed.ok) {
      setNodes(
        Object.fromEntries(listed.data.map((node) => [node.node, node])),
      );
    }
    setError(found.ok ? (listed.ok ? undefined : listed.error) : found.error);
  }, [clients, run]);

  useEffect(() => {
    if (auth.status !== "signed-in" || run === null) return;
    // oxlint-disable-next-line react/set-state-in-effect -- refresh sets state only after the RPCs resolve.
    void refresh();
    // oxlint-disable-next-line react/exhaustive-effect-dependencies -- userId reloads for the new user.
  }, [run, userId, auth.status, refresh]);

  const id = current?.id ?? null;
  useEffect(() => {
    if (auth.status !== "signed-in" || id === null) return;
    return watchTopic(supabase, `workflow-run:${id}`, {
      onMessage: () => void refresh(),
      onRejoin: () => void refresh(),
      onStatus: setStatus,
    });
  }, [supabase, id, auth.status, refresh]);

  return { run: current, nodes, error, status, refresh };
}
