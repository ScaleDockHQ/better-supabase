"use client";

import { useCallback, useEffect, useMemo, useState } from "react";

import type { DbError } from "../../../core/errors.ts";
import type { SubscriptionStatus } from "../../../realtime/index.ts";
import type { WorkflowRun, WorkflowRunStatus } from "../workflows.ts";

import { rpcTransport } from "../../../core/block-transport.ts";
import { useAuth, useSupabase } from "../../../react/hooks.ts";
import { watchTopic } from "../../react-topic.ts";
import { createWorkflows } from "../workflows.ts";

export interface UseWorkflowRunsOptions {
  /** The tenant whose runs to list; it also joins the tenant's `workflow-runs:<tenant>` topic. Without one, the signed-in user's own runs load once. */
  readonly tenant?: string | null;
  readonly definition?: string;
  readonly status?: WorkflowRunStatus;
  readonly limit?: number;
  /** The schema the calls go to: the module schema (default `better_supabase`), or the API schema from `sql.modules.workflows.api`. */
  readonly schema?: string;
}

export interface WorkflowRunsState {
  /** `undefined` until the first load. */
  readonly runs: readonly WorkflowRun[] | undefined;
  readonly error: DbError | undefined;
  readonly status: SubscriptionStatus;
  readonly refresh: () => Promise<void>;
}

/**
 * The runs the signed-in user may read, newest first, loaded again when a
 * run in the tenant changes status.
 *
 * ```tsx
 * const { runs } = useWorkflowRuns({ tenant: organizationId });
 * ```
 */
export function useWorkflowRuns(
  options: UseWorkflowRunsOptions = {},
): WorkflowRunsState {
  const supabase = useSupabase();
  const auth = useAuth();
  const [runs, setRuns] = useState<readonly WorkflowRun[] | undefined>(
    undefined,
  );
  const [error, setError] = useState<DbError | undefined>(undefined);
  const [status, setStatus] = useState<SubscriptionStatus>("closed");
  const { schema, definition, limit } = options;
  const runStatus = options.status;
  const tenant = options.tenant ?? null;
  const workflows = useMemo(
    () =>
      createWorkflows({
        transport: rpcTransport(supabase),
        ...(schema === undefined ? {} : { schema }),
      }),
    [supabase, schema],
  );
  const userId = auth.user?.id ?? null;

  const refresh = useCallback(async () => {
    const result = await workflows.runs.list({
      ...(tenant === null ? {} : { tenant }),
      ...(definition === undefined ? {} : { definition }),
      ...(runStatus === undefined ? {} : { status: runStatus }),
      ...(limit === undefined ? {} : { limit }),
    });
    if (result.ok) {
      setRuns(result.data);
      setError(undefined);
    } else {
      setError(result.error);
    }
  }, [workflows, tenant, definition, runStatus, limit]);

  useEffect(() => {
    if (auth.status !== "signed-in") return;
    // oxlint-disable-next-line react/set-state-in-effect -- refresh sets state only after the RPC resolves.
    void refresh();
    if (tenant === null) return;
    return watchTopic(supabase, `workflow-runs:${tenant}`, {
      onMessage: () => void refresh(),
      onRejoin: () => void refresh(),
      onStatus: setStatus,
    });
    // oxlint-disable-next-line react/exhaustive-effect-dependencies -- userId reloads and resubscribes for the new user.
  }, [supabase, tenant, userId, auth.status, refresh]);

  return { runs, error, status, refresh };
}

export interface UseWorkflowRunOptions {
  readonly schema?: string;
}

export interface WorkflowRunState {
  /** `undefined` until the first load, and when the user may not read the run. */
  readonly run: WorkflowRun | undefined;
  readonly error: DbError | undefined;
  readonly status: SubscriptionStatus;
  readonly refresh: () => Promise<void>;
  /** Asks the engine to cancel the run, then loads it again. */
  readonly cancel: () => Promise<void>;
}

/**
 * One run by its id or its engine's id, loaded again on each status change
 * broadcast on `workflow-run:<id>`.
 */
export function useWorkflowRun(
  run: string | null,
  options: UseWorkflowRunOptions = {},
): WorkflowRunState {
  const supabase = useSupabase();
  const auth = useAuth();
  const [current, setCurrent] = useState<WorkflowRun | undefined>(undefined);
  const [error, setError] = useState<DbError | undefined>(undefined);
  const [status, setStatus] = useState<SubscriptionStatus>("closed");
  const schema = options.schema;
  const workflows = useMemo(
    () =>
      createWorkflows({
        transport: rpcTransport(supabase),
        ...(schema === undefined ? {} : { schema }),
      }),
    [supabase, schema],
  );
  const userId = auth.user?.id ?? null;

  const refresh = useCallback(async () => {
    if (run === null) return;
    const result = await workflows.runs.get(run);
    if (result.ok) {
      setCurrent(result.data);
      setError(undefined);
    } else {
      setError(result.error);
    }
  }, [workflows, run]);

  const cancel = useCallback(async () => {
    if (run === null) return;
    const result = await workflows.runs.requestCancel(run);
    if (result.ok) await refresh();
    else setError(result.error);
  }, [workflows, run, refresh]);

  useEffect(() => {
    if (auth.status !== "signed-in" || run === null) return;
    // oxlint-disable-next-line react/set-state-in-effect -- refresh sets state only after the RPC resolves.
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

  return { run: current, error, status, refresh, cancel };
}
