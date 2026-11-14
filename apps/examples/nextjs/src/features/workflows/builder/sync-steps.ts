import {
  createWorkflowEditor,
  rpcTransport,
  subscribeEventTriggers,
} from "better-supabase/blocks/workflow-editor";
import { graphStarter } from "better-supabase/workflow-sdk/builder";

import { bsbCore } from "@/lib/supabase/server-core";

import { graphSteps, requestGraphApproval } from "./graph-steps";
import { allNodeSteps, graphExecutor } from "./graph-workflow";
import { nodeKinds } from "./node-kinds";
import { stepLibrary } from "./step-library";

/**
 * Writes the step library and the node kind registry, so the canvas offers the
 * steps this deployment has and publishing accepts graphs that use them. A
 * database that is down at start-up leaves the previous library in place.
 */
export async function syncStepLibrary(): Promise<void> {
  const builder = createWorkflowEditor({
    transport: rpcTransport(bsbCore.admin().$client, { schema: "api" }),
    schema: "api",
    steps: stepLibrary,
    nodes: nodeKinds,
  });

  const [synced, kinds] = await Promise.all([
    builder.steps.sync(),
    builder.nodeKinds.sync(),
  ]);

  if (!synced.ok) {
    console.warn(`Step library not synced: ${synced.error.message}`);
  }

  if (!kinds.ok) {
    console.warn(`Node kinds not synced: ${kinds.error.message}`);
  }
}

let stopEventTriggers: (() => void) | undefined;

/**
 * Starts the runs of `event` triggers from the block events this server emits.
 * Start-up calls it once; a hot reload replaces the earlier subscription. A
 * trigger that fails to start is logged and never changes the work that emitted
 * the event.
 */
export function startEventTriggers(): void {
  stopEventTriggers?.();

  stopEventTriggers = subscribeEventTriggers(
    bsbCore,
    createWorkflowEditor({
      transport: rpcTransport(bsbCore.admin().$client, { schema: "api" }),
      service: rpcTransport(bsbCore.admin().$client, { schema: "api" }),
      schema: "api",
      steps: stepLibrary,
      nodes: nodeKinds,
      start: graphStarter({
        steps: graphSteps,
        nodeKinds,
        nodes: allNodeSteps,
        executor: graphExecutor,
        executorRunsTests: true,
        approval: requestGraphApproval,
      }),
    }),
    {
      onError: ({ error, eventType }) => {
        console.warn(
          `Event trigger for ${eventType} did not start: ${error.message}`,
        );
      },
    },
  );
}
