import type {
  GraphRuntime,
  GraphStepCall,
} from "../../../src/blocks/workflow-editor/executor.ts";
import type {
  WorkflowGraph,
  WorkflowGraphNode,
  WorkflowNodeKindInfo,
} from "../../../src/blocks/workflow-editor/graph.ts";

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
    requestApproval: async (call) => `${call.runKey}:${call.node}`,
    approval: async (token, node) => {
      log.push(`approval ${token} ${node}`);

      return approval;
    },
  };
}

/** A graph with the app's own kinds: a branching score check and a notify. */
export const CUSTOM_GRAPH: WorkflowGraph = {
  nodes: [
    { id: "start", kind: "trigger" },
    { id: "score", kind: "score.check", config: { min: 5 } },
    { id: "ping", kind: "notify", config: { channel: "ops" } },
    { id: "skip", kind: "notify", config: { channel: "low" } },
  ],
  edges: [
    { id: "e1", source: "start", target: "score" },
    { id: "e2", source: "score", target: "ping", branch: "true" },
    { id: "e3", source: "score", target: "skip", branch: "false" },
  ],
};

export const CUSTOM_KINDS: readonly WorkflowNodeKindInfo[] = [
  { kind: "score.check", branches: true },
  {
    kind: "notify",
    validate: (node: WorkflowGraphNode) =>
      typeof node.config?.["channel"] === "string"
        ? []
        : [`Node ${node.id} names no channel`],
  },
];
