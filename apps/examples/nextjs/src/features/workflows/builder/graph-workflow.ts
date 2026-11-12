import type {
  GraphNodeCall,
  GraphStepCall,
  RunInput,
  WorkflowGraph,
} from "better-supabase/blocks/workflow-editor";
import type { GraphRunMeta } from "better-supabase/workflow-sdk/builder";

import {
  createWorkflowEditor,
  executeGraph,
  graphRunFields,
  rpcTransport,
} from "better-supabase/blocks/workflow-editor";
import {
  compileGraph,
  graphStarter,
} from "better-supabase/workflow-sdk/builder";
import { Temporal } from "temporal-polyfill";
import { createHook, sleep } from "workflow";

import { serviceSupabase } from "../workflow-steps";
import {
  graphNodeSteps,
  graphSteps,
  reportNode,
  requestGraphApproval,
  runOwner,
  text,
  withConfig,
} from "./graph-steps";
import { nodeKinds } from "./node-kinds";
import { stepLibrary } from "./step-library";

type Writable<T> = { -readonly [K in keyof T]: T[K] };

const isStep = (name: string): name is keyof typeof graphSteps =>
  Object.hasOwn(graphSteps, name);

const isNode = (kind: string): kind is keyof typeof graphNodeSteps =>
  Object.hasOwn(graphNodeSteps, kind);

/**
 * The `sub-workflow` node: starts another definition's published version and
 * returns its run id. It lives here, not in `graph-steps.ts`, because the
 * starter needs the executor below, which imports the steps. The run is keyed
 * on the parent's run key and node, so a retried step starts one child.
 */
async function subWorkflowNode(call: GraphNodeCall) {
  "use step";

  return reportNode(call, async () => {
    const config = withConfig(call).config;
    const { tenant, actor } = await runOwner();
    const transport = rpcTransport(serviceSupabase(), { schema: "api" });

    const builder = createWorkflowEditor({
      transport,
      schema: "api",
      steps: stepLibrary,
      nodes: nodeKinds,
      compile: (graph) => compileGraph(graph, { nodes: nodeKinds }),
      start: graphStarter({
        steps: graphSteps,
        nodeKinds,
        nodes: { ...graphNodeSteps, "sub-workflow": subWorkflowNode },
        executor: graphExecutor,
        executorRunsTests: true,
        approval: requestGraphApproval,
      }),
      temporal: Temporal,
    });

    const request: Writable<RunInput> = {
      definition: text(config, "definition"),
      input: { text: text(config, "text") },
      idempotencyKey: `${call.runKey}:${call.node}`,
    };

    if (actor !== undefined) {
      request.actor = actor;
    }

    if (tenant !== undefined) {
      request.tenant = tenant;
    }

    const runId = await builder.run(request).orThrow();

    return { runId };
  });
}

/** The deployment's node steps by kind, the `nodes` of `graphStarter`. */
export const allNodeSteps = {
  ...graphNodeSteps,
  "sub-workflow": subWorkflowNode,
};

/**
 * The static executor: walks a published graph when dynamic workflows
 * (`WORKFLOW_EXPERIMENTAL_DYNAMIC_WORKFLOWS`) are off. It imports the
 * engine-neutral block, which loads nothing the workflow sandbox lacks.
 */
export async function graphExecutor(
  graph: WorkflowGraph,
  input: GraphStepCall["input"],
  meta: GraphRunMeta,
): ReturnType<typeof executeGraph> {
  "use workflow";

  return executeGraph(graph, input, {
    ...graphRunFields(meta),
    nodes: nodeKinds,
    step: (call) => {
      if (!isStep(call.step)) {
        throw new Error(`Unknown step ${call.step}`);
      }

      return graphSteps[call.step](call);
    },
    node: (call) => {
      if (call.kind === "sub-workflow") {
        return subWorkflowNode(call);
      }

      if (!isNode(call.kind)) {
        throw new Error(`Unknown node kind ${call.kind}`);
      }

      return graphNodeSteps[call.kind](call);
    },
    sleep: (ms) => sleep(ms),
    requestApproval: (call) => requestGraphApproval(call),
    approval: (token) => createHook<unknown>({ token }),
  });
}
