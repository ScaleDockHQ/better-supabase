import type {
  GraphRuntime,
  GraphStepCall,
} from "../../../src/blocks/workflow-builder/executor.ts";
import type { WorkflowGraph } from "../../../src/blocks/workflow-builder/graph.ts";

export const GRAPH: WorkflowGraph = {
  nodes: [
    { id: "start", kind: "trigger" },
    { id: "lookup", kind: "step", step: "crm.lookup" },
    {
      id: "isPro",
      kind: "condition",
      config: { path: "results.lookup.plan", op: "equals", value: "pro" },
    },
    { id: "wait", kind: "sleep", config: { duration: "2h" } },
    { id: "ok", kind: "approval" },
    {
      id: "welcome",
      kind: "step",
      step: "email.send",
      config: { template: "pro" },
    },
    {
      id: "nudge",
      kind: "step",
      step: "email.send",
      config: { template: "free" },
    },
    { id: "rejected", kind: "step", step: "slack.post" },
  ],
  edges: [
    { id: "e1", source: "start", target: "lookup" },
    { id: "e2", source: "lookup", target: "isPro" },
    { id: "e3", source: "isPro", target: "wait", branch: "true" },
    { id: "e4", source: "wait", target: "ok" },
    { id: "e5", source: "ok", target: "welcome", branch: "true" },
    { id: "e6", source: "ok", target: "rejected", branch: "false" },
    { id: "e7", source: "isPro", target: "nudge", branch: "false" },
  ],
};

export function fakeRuntime(
  plan: string,
  approval: unknown,
): GraphRuntime & { readonly log: string[] } {
  const log: string[] = [];
  return {
    log,
    runKey: "run-1",
    step: async (call: GraphStepCall) => {
      log.push(`step ${call.node} ${call.step} ${JSON.stringify(call.config)}`);
      return call.step === "crm.lookup" ? { plan } : undefined;
    },
    sleep: async (ms) => {
      log.push(`sleep ${String(ms)}`);
    },
    approval: async (token, node) => {
      log.push(`approval ${token} ${node}`);
      return approval;
    },
  };
}
