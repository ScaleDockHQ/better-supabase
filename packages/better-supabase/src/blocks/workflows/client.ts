import type { DbError } from "../../core/errors.ts";
import type { SubscriptionStatus } from "../../realtime/index.ts";
import type { TopicPort } from "../../realtime/watch-topic.ts";
import type { AuthPort, Controller } from "../controller.ts";
import type { WorkflowRun, WorkflowRunStatus, Workflows } from "./workflows.ts";

import { defineController, whileSignedIn } from "../controller.ts";
import { watchRun } from "./run-watch.ts";

export interface WorkflowRunsControllerOptions {
  readonly client: { readonly runs: Pick<Workflows["runs"], "list"> };
  readonly auth: AuthPort;
  readonly ports: { readonly topic: TopicPort };
  /** The tenant whose runs to list; it also joins the tenant's `workflow-runs:<tenant>` topic. Without one, the signed-in user's own runs load once. */
  readonly tenant?: string | null;
  readonly definition?: string;
  readonly status?: WorkflowRunStatus;
  readonly limit?: number;
}

export interface WorkflowRunsSnapshot {
  /** `undefined` until the first load. */
  readonly runs: readonly WorkflowRun[] | undefined;
  readonly error: DbError | undefined;
  readonly status: SubscriptionStatus;
}

export interface WorkflowRunsActions {
  readonly refresh: () => Promise<void>;
}

export type WorkflowRunsController = Controller<
  WorkflowRunsSnapshot,
  WorkflowRunsActions
>;

/**
 * The runs the signed-in user may read, newest first, loaded again when a
 * run in the tenant changes status.
 */
export function createWorkflowRunsController(
  options: WorkflowRunsControllerOptions,
): WorkflowRunsController {
  const tenant = options.tenant ?? null;
  const { definition, limit } = options;
  const runStatus = options.status;
  return defineController<WorkflowRunsSnapshot, WorkflowRunsActions>(
    { runs: undefined, error: undefined, status: "closed" },
    (state) => {
      const refresh = async (): Promise<void> => {
        const run = state.run();
        const result = await options.client.runs.list({
          ...(tenant === null ? {} : { tenant }),
          ...(definition === undefined ? {} : { definition }),
          ...(runStatus === undefined ? {} : { status: runStatus }),
          ...(limit === undefined ? {} : { limit }),
        });
        if (run !== state.run()) {
          return;
        }
        state.set(
          result.ok
            ? { runs: result.data, error: undefined }
            : { error: result.error },
        );
      };
      return {
        actions: { refresh },
        start: () =>
          whileSignedIn(options.auth, () => {
            void refresh();
            if (tenant === null) {
              return;
            }
            return options.ports.topic(`workflow-runs:${tenant}`, {
              onMessage: () => void refresh(),
              onRejoin: () => void refresh(),
              onStatus: (status) => {
                state.set({ status });
              },
            }).leave;
          }),
      };
    },
  );
}

export interface WorkflowRunControllerOptions {
  readonly client: {
    readonly runs: Pick<Workflows["runs"], "get" | "requestCancel">;
  };
  readonly auth: AuthPort;
  readonly ports: { readonly topic: TopicPort };
  /** The run's id or its engine's id; `null` waits. */
  readonly run: string | null;
}

export interface WorkflowRunSnapshot {
  /** `undefined` until the first load, and when the user may not read the run. */
  readonly run: WorkflowRun | undefined;
  readonly error: DbError | undefined;
  readonly status: SubscriptionStatus;
}

export interface WorkflowRunActions {
  readonly refresh: () => Promise<void>;
  /** Asks the engine to cancel the run, then loads it again. */
  readonly cancel: () => Promise<void>;
}

export type WorkflowRunController = Controller<
  WorkflowRunSnapshot,
  WorkflowRunActions
>;

/**
 * One run by its id or its engine's id, loaded again on each status change
 * broadcast on `workflow-run:<id>`.
 */
export function createWorkflowRunController(
  options: WorkflowRunControllerOptions,
): WorkflowRunController {
  const { client, run } = options;
  return defineController<WorkflowRunSnapshot, WorkflowRunActions>(
    { run: undefined, error: undefined, status: "closed" },
    (state) => {
      const watch = watchRun<WorkflowRunSnapshot>(
        {
          ...options,
          load: async () => {
            const result = await client.runs.get(run ?? "");
            return result.ok
              ? {
                  id: result.data?.id ?? null,
                  patch: { run: result.data, error: undefined },
                }
              : { id: null, patch: { error: result.error } };
          },
        },
        state,
      );
      return {
        actions: {
          refresh: watch.refresh,
          cancel: async () => {
            if (run === null) {
              return;
            }
            const result = await client.runs.requestCancel(run);
            if (result.ok) {
              await watch.refresh();
            } else {
              state.set({ error: result.error });
            }
          },
        },
        start: watch.start,
      };
    },
  );
}
