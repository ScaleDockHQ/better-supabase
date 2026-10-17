import {
  approved,
  conditionOf,
  durationMs,
  evaluateCondition,
  isGraphRecord,
  topologicalOrder,
  validateGraph,
  type WorkflowGraph,
  type WorkflowGraphEdge,
  type WorkflowGraphNode,
} from "./graph.ts";

/** The record a run belongs to. */
export interface GraphSubject {
  readonly type: string;
  readonly id: string;
}

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
  /** The tenant the run belongs to; pass it to `builder.versions.runAs` too. */
  readonly tenant?: string;
  readonly subject?: GraphSubject;
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
  readonly tenant?: string;
  readonly subject?: GraphSubject;
}

/** What the engine does for each kind of node. */
export interface GraphRuntime {
  readonly runKey: string;
  /** The published version's id (`GraphRunMeta.versionId`), passed to each step. */
  readonly version?: string;
  /** The run's tenant, passed to each step. */
  readonly tenant?: string;
  /** The record the run belongs to: passed to each step, and conditions read it as `subject`. */
  readonly subject?: GraphSubject;
  /** The trigger node the run starts at; required when the graph has several. */
  readonly triggerNode?: string;
  /**
   * Set for a test run: each step node returns its stub (by node id, else
   * `{ stubbed: true }`) instead of calling `step`, sleeps are skipped, and
   * an approval node takes its stub as the decision (else approved).
   */
  readonly stubs?: Readonly<Record<string, unknown>>;
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
  if (outcome === undefined) {
    return false;
  }
  return edge.branch === undefined || String(outcome) === edge.branch;
};

/** The run fields a graph run's meta carries (`GraphRunMeta` in `workflow-sdk/builder`). */
export type GraphRunFields = Pick<
  GraphRuntime,
  "runKey" | "version" | "tenant" | "subject" | "triggerNode" | "stubs"
>;

/**
 * The runtime fields of a static executor's `meta`: spread them into the
 * runtime passed to `executeGraph`, so a run starts at its trigger node,
 * conditions read its subject, and a test run returns its stubs instead of
 * running steps.
 */
export function graphRunFields(meta: unknown): GraphRunFields {
  const record = isGraphRecord(meta) ? meta : {};
  const text = (key: string): string | undefined =>
    typeof record[key] === "string" ? record[key] : undefined;
  const subject = record["subject"];
  const stubs = record["stubs"];
  const version = text("versionId");
  const tenant = text("tenant");
  const triggerNode = text("triggerNode");
  return {
    runKey: text("runKey") ?? "",
    ...(version === undefined ? {} : { version }),
    ...(tenant === undefined ? {} : { tenant }),
    ...(isGraphRecord(subject)
      ? {
          subject: { type: String(subject["type"]), id: String(subject["id"]) },
        }
      : {}),
    ...(triggerNode === undefined ? {} : { triggerNode }),
    ...(record["mode"] === "test"
      ? { stubs: isGraphRecord(stubs) ? stubs : {} }
      : {}),
  };
}

/** A test run's stub for `node`, or `fallback` when it has none. */
function stubOf(
  stubs: Readonly<Record<string, unknown>>,
  node: string,
  fallback: unknown,
): unknown {
  return Object.hasOwn(stubs, node) ? stubs[node] : fallback;
}

/**
 * The trigger node a run starts at: `requested` when the graph has it, else
 * the graph's only trigger. Throws when neither picks one.
 */
export function startNodeOf(
  graph: WorkflowGraph,
  requested: string | undefined,
): string {
  const triggers = graph.nodes.filter((node) => node.kind === "trigger");
  const start =
    requested === undefined
      ? triggers.length === 1
        ? triggers[0]?.id
        : undefined
      : triggers.find((node) => node.id === requested)?.id;
  if (start === undefined) {
    throw new TypeError(
      "workflow-builder: pass the trigger node the run starts at, the id of one of the graph's trigger nodes",
    );
  }
  return start;
}

/**
 * Runs `graph` in dependency order from its start trigger
 * (`runtime.triggerNode`): a node runs when the trigger reaches it through
 * edges whose sources ran (and, from a condition or an approval, took the
 * edge's branch). Returns each node's output by id. It only calls
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
  const start = startNodeOf(graph, runtime.triggerNode);
  const order = topologicalOrder(graph) ?? [];
  const incoming = new Map<string, WorkflowGraphEdge[]>();
  for (const edge of graph.edges) {
    incoming.set(edge.target, [...(incoming.get(edge.target) ?? []), edge]);
  }
  const results: Record<string, unknown> = {};
  const ran = new Map<string, boolean>();
  for (const node of order) {
    if (node.kind === "trigger") {
      if (node.id !== start) {
        continue;
      }
    } else {
      const edges = incoming.get(node.id) ?? [];
      if (!edges.some((edge) => active(edge, ran))) {
        continue;
      }
    }
    const { output, outcome } = await runNode(node, input, results, runtime);
    results[node.id] = output;
    ran.set(node.id, outcome);
  }
  return results;
}

const extrasOf = (
  runtime: GraphRuntime,
): Pick<GraphStepCall, "version" | "tenant" | "subject"> => ({
  ...(runtime.version === undefined ? {} : { version: runtime.version }),
  ...(runtime.tenant === undefined ? {} : { tenant: runtime.tenant }),
  ...(runtime.subject === undefined ? {} : { subject: runtime.subject }),
});

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
      const output =
        runtime.stubs === undefined
          ? await runtime.step({
              node: node.id,
              step: node.step ?? "",
              config: node.config ?? {},
              input,
              results: { ...results },
              runKey: runtime.runKey,
              ...extrasOf(runtime),
            })
          : stubOf(runtime.stubs, node.id, { stubbed: true });
      return { output: output ?? null, outcome: true };
    }
    case "sleep": {
      if (runtime.stubs === undefined) {
        await runtime.sleep(durationMs(node.config?.["duration"]) ?? 0);
      }
      return { output: null, outcome: true };
    }
    case "approval": {
      if (runtime.stubs !== undefined) {
        const payload = stubOf(runtime.stubs, node.id, { approved: true });
        return { output: payload ?? null, outcome: approved(payload) };
      }
      const token =
        runtime.requestApproval === undefined
          ? approvalToken(runtime.runKey, node.id)
          : await runtime.requestApproval({
              node: node.id,
              config: node.config ?? {},
              input,
              results: { ...results },
              runKey: runtime.runKey,
              ...extrasOf(runtime),
            });
      const payload = await runtime.approval(token, node.id);
      return { output: payload ?? null, outcome: approved(payload) };
    }
    case "condition": {
      const condition = conditionOf(node);
      const outcome =
        condition !== undefined &&
        evaluateCondition(condition, {
          input,
          results,
          subject: runtime.subject,
        });
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
