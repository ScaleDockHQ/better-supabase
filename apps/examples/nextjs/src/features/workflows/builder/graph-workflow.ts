import {
  executeGraph,
  type GraphStepCall,
  type WorkflowGraph,
} from "better-supabase/blocks/workflow-builder";
import { createHook, sleep } from "workflow";

import { graphSteps } from "./graph-steps";

const isStep = (name: string): name is keyof typeof graphSteps =>
  Object.hasOwn(graphSteps, name);

/**
 * The static executor: walks a published graph when dynamic workflows
 * (`WORKFLOW_EXPERIMENTAL_DYNAMIC_WORKFLOWS`) are off. It imports the
 * engine-neutral block, which loads nothing the workflow sandbox lacks.
 */
export async function graphExecutor(
  graph: WorkflowGraph,
  input: GraphStepCall["input"],
  meta: { readonly runKey: string },
): ReturnType<typeof executeGraph> {
  "use workflow";
  return executeGraph(graph, input, {
    runKey: meta.runKey,
    step: (call) => {
      if (!isStep(call.step)) throw new Error(`Unknown step ${call.step}`);
      return graphSteps[call.step](call);
    },
    sleep: (ms) => sleep(ms),
    approval: (token) => createHook<unknown>({ token }),
  });
}
