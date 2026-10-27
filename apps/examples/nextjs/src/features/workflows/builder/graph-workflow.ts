import type {
  GraphStepCall,
  WorkflowGraph,
} from "better-supabase/blocks/workflow-editor";
import type { GraphRunMeta } from "better-supabase/workflow-sdk/builder";

import {
  executeGraph,
  graphRunFields,
} from "better-supabase/blocks/workflow-editor";
import { createHook, sleep } from "workflow";

import { graphSteps, requestGraphApproval } from "./graph-steps";

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
  meta: GraphRunMeta,
): ReturnType<typeof executeGraph> {
  "use workflow";

  return executeGraph(graph, input, {
    ...graphRunFields(meta),
    step: (call) => {
      if (!isStep(call.step)) {
        throw new Error(`Unknown step ${call.step}`);
      }

      return graphSteps[call.step](call);
    },
    sleep: (ms) => sleep(ms),
    requestApproval: (call) => requestGraphApproval(call),
    approval: (token) => createHook<unknown>({ token }),
  });
}
