import type { DbError } from "../../core/errors.ts";
import type { SubscriptionStatus } from "../../realtime/index.ts";
import type { TopicPort } from "../../realtime/watch-topic.ts";
import type { AuthPort, Controller } from "../controller.ts";
import type { WorkflowRun, Workflows } from "../workflows/workflows.ts";
import type {
  WorkflowEditor,
  WorkflowDefinition,
  WorkflowNodeRun,
  WorkflowStepInfo,
} from "./workflow-editor.ts";

import { defineController, whileSignedIn } from "../controller.ts";
import { firstError, watchRun } from "../workflows/run-watch.ts";

export interface WorkflowEditorControllerOptions {
  readonly client: {
    readonly definitions: Pick<WorkflowEditor["definitions"], "list">;
    readonly steps: Pick<WorkflowEditor["steps"], "list">;
  };
  readonly auth: AuthPort;
  /** The tenant whose definitions to list. */
  readonly tenant?: string | null;
}

export interface WorkflowEditorSnapshot {
  /** `undefined` until the first load. */
  readonly definitions: readonly WorkflowDefinition[] | undefined;
  /** The step library, the canvas's palette. */
  readonly steps: readonly WorkflowStepInfo[] | undefined;
  readonly error: DbError | undefined;
}

export interface WorkflowEditorActions {
  readonly refresh: () => Promise<void>;
}

export type WorkflowEditorController = Controller<
  WorkflowEditorSnapshot,
  WorkflowEditorActions
>;

/** The definitions the signed-in user may read and the step library. */
export function createWorkflowEditorController(
  options: WorkflowEditorControllerOptions,
): WorkflowEditorController {
  const tenant = options.tenant ?? null;

  return defineController<WorkflowEditorSnapshot, WorkflowEditorActions>(
    { definitions: undefined, steps: undefined, error: undefined },
    (state) => {
      const refresh = async (): Promise<void> => {
        const run = state.run();

        const [listed, library] = await Promise.all([
          options.client.definitions.list(tenant ?? undefined),
          options.client.steps.list(),
        ]);

        if (run !== state.run()) {
          return;
        }

        state.set({
          ...(listed.ok ? { definitions: listed.data } : {}),
          ...(library.ok ? { steps: library.data } : {}),
          error: firstError(listed, library),
        });
      };

      return {
        actions: { refresh },
        start: () =>
          whileSignedIn(options.auth, () => {
            void refresh();

            return;
          }),
      };
    },
  );
}

export interface WorkflowCanvasRunControllerOptions {
  readonly client: {
    readonly runs: Pick<Workflows["runs"], "get">;
    readonly nodeRuns: Pick<WorkflowEditor["nodeRuns"], "list">;
  };
  readonly auth: AuthPort;
  readonly ports: { readonly topic: TopicPort };
  /** The run's id or its engine's id; `null` waits. */
  readonly run: string | null;
}

export interface WorkflowCanvasRunSnapshot {
  readonly run: WorkflowRun | undefined;
  /** Each node's status by node id, for the canvas overlay. */
  readonly nodes: Readonly<Record<string, WorkflowNodeRun>>;
  readonly error: DbError | undefined;
  readonly status: SubscriptionStatus;
}

export interface WorkflowCanvasRunActions {
  readonly refresh: () => Promise<void>;
}

export type WorkflowCanvasRunController = Controller<
  WorkflowCanvasRunSnapshot,
  WorkflowCanvasRunActions
>;

const NO_NODES: Readonly<Record<string, WorkflowNodeRun>> = {};

/**
 * A run and the status of each of its nodes, loaded again on each message on
 * `workflow-run:<id>` (run status changes and node records).
 */
export function createWorkflowCanvasRunController(
  options: WorkflowCanvasRunControllerOptions,
): WorkflowCanvasRunController {
  const { client } = options;
  const run = options.run ?? "";

  return defineController<WorkflowCanvasRunSnapshot, WorkflowCanvasRunActions>(
    { run: undefined, nodes: NO_NODES, error: undefined, status: "closed" },
    (state) => {
      const watch = watchRun<WorkflowCanvasRunSnapshot>(
        {
          ...options,
          load: async () => {
            const [found, listed] = await Promise.all([
              client.runs.get(run),
              client.nodeRuns.list(run),
            ]);

            return {
              id: found.ok ? (found.data?.id ?? null) : null,
              patch: {
                ...(found.ok ? { run: found.data } : {}),
                ...(listed.ok
                  ? {
                      nodes: Object.fromEntries(
                        listed.data.map((node) => [node.node, node]),
                      ),
                    }
                  : {}),
                error: firstError(found, listed),
              },
            };
          },
        },
        state,
      );

      return { actions: { refresh: watch.refresh }, start: watch.start };
    },
  );
}
