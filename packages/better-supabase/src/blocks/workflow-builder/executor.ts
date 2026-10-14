import {
  approved,
  conditionOf,
  durationMs,
  evaluateCondition,
  topologicalOrder,
  validateGraph,
  type WorkflowGraph,
  type WorkflowGraphEdge,
  type WorkflowGraphNode,
} from "./graph.ts";

/** What a step node passes to the engine's step: plain data, so it serializes. */
export interface GraphStepCall {
  /** The node id, which `workflow_node_runs` keys on. */
  readonly node: string;
  /** The library step's name. */
  readonly step: string;
  readonly config: Readonly<Record<string, unknown>>;
  /** The trigger's input. */
  readonly input: unknown;
  /** The outputs of the nodes that ran before it, by node id. */
  readonly results: Readonly<Record<string, unknown>>;
  /** The run's key; approval hooks use `<runKey>:<node>` as their token. */
  readonly runKey: string;
  /** The published version's id; pass it to `builder.versions.runAs`. */
  readonly version?: string;
}

/** What an approval node passes to `GraphRuntime.requestApproval`: plain data, so it serializes. */
export interface GraphApprovalCall {
  readonly node: string;
  /** The node's config, e.g. the approvals `action` to file the request under. */
  readonly config: Readonly<Record<string, unknown>>;
  readonly input: unknown;
  readonly results: Readonly<Record<string, unknown>>;
  readonly runKey: string;
  readonly version?: string;
}

/** What the engine does for each kind of node. */
export interface GraphRuntime {
  readonly runKey: string;
  /** The published version's id (`GraphRunMeta.versionId`), passed to each step. */
  readonly version?: string;
  step(call: GraphStepCall): PromiseLike<unknown>;
  sleep(ms: number): PromiseLike<unknown>;
  /**
   * Files the approval request for an approval node and returns its id,
   * which becomes the hook token. Run it as a step that calls the approvals
   * block's `request`; `wakeOnApproval` resumes the run once an eligible
   * approver decides. Without it the token is `<runKey>:<node>`, which
   * anyone who knows the run key can guess.
   */
  requestApproval?(call: GraphApprovalCall): PromiseLike<string>;
  /** Waits for the approval hook with `token` and returns its payload. */
  approval(token: string, node: string): PromiseLike<unknown>;
}

/** The hook token of an approval node without `requestApproval`. */
export const approvalToken = (runKey: string, node: string): string =>
  `${runKey}:${node}`;

const active = (
  edge: WorkflowGraphEdge,
  ran: ReadonlyMap<string, boolean>,
): boolean => {
  const outcome = ran.get(edge.source);
  if (outcome === undefined) return false;
  return edge.branch === undefined || String(outcome) === edge.branch;
};

/**
 * Runs `graph` in dependency order: a node runs when the trigger reaches it
 * through edges whose sources ran (and, from a condition or an approval,
 * took the edge's branch). Returns each node's output by id. It only calls
 * `runtime`, so it is deterministic and runs inside a `"use workflow"`
 * function as the static executor.
 */
export async function executeGraph(
  graph: WorkflowGraph,
  input: unknown,
  runtime: GraphRuntime,
): Promise<Record<string, unknown>> {
  const errors = validateGraph(graph);
  if (errors.length > 0) {
    throw new TypeError(`workflow-builder: ${errors.join("; ")}`);
  }
  const order = topologicalOrder(graph) ?? [];
  const incoming = new Map<string, WorkflowGraphEdge[]>();
  for (const edge of graph.edges) {
    incoming.set(edge.target, [...(incoming.get(edge.target) ?? []), edge]);
  }
  const results: Record<string, unknown> = {};
  const ran = new Map<string, boolean>();
  for (const node of order) {
    if (node.kind !== "trigger") {
      const edges = incoming.get(node.id) ?? [];
      if (!edges.some((edge) => active(edge, ran))) continue;
    }
    const { output, outcome } = await runNode(node, input, results, runtime);
    results[node.id] = output;
    ran.set(node.id, outcome);
  }
  return results;
}

async function runNode(
  node: WorkflowGraphNode,
  input: unknown,
  results: Readonly<Record<string, unknown>>,
  runtime: GraphRuntime,
): Promise<{ output: unknown; outcome: boolean }> {
  switch (node.kind) {
    case "trigger": {
      return { output: input, outcome: true };
    }
    case "step": {
      const output = await runtime.step({
        node: node.id,
        step: node.step ?? "",
        config: node.config ?? {},
        input,
        results: { ...results },
        runKey: runtime.runKey,
        ...(runtime.version === undefined ? {} : { version: runtime.version }),
      });
      return { output: output ?? null, outcome: true };
    }
    case "sleep": {
      await runtime.sleep(durationMs(node.config?.["duration"]) ?? 0);
      return { output: null, outcome: true };
    }
    case "approval": {
      const token =
        runtime.requestApproval === undefined
          ? approvalToken(runtime.runKey, node.id)
          : await runtime.requestApproval({
              node: node.id,
              config: node.config ?? {},
              input,
              results: { ...results },
              runKey: runtime.runKey,
              ...(runtime.version === undefined
                ? {}
                : { version: runtime.version }),
            });
      const payload = await runtime.approval(token, node.id);
      return { output: payload ?? null, outcome: approved(payload) };
    }
    case "condition": {
      const condition = conditionOf(node);
      const outcome =
        condition !== undefined &&
        evaluateCondition(condition, { input, results });
      return { output: outcome, outcome };
    }
    default: {
      const unknown: never = node.kind;
      throw new TypeError(
        `workflow-builder: unknown node kind ${String(unknown)}`,
      );
    }
  }
}
