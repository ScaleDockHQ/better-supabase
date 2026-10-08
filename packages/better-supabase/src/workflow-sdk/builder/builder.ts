import type { World } from "@workflow/world";

import { getStepMetadata, getWorkflowMetadata } from "workflow";
import { start } from "workflow/api";

import type { GraphStepCall } from "../../blocks/workflow-builder/executor.ts";
import type {
  BuilderStartCall,
  BuilderStarter,
  NodeRunRecord,
} from "../../blocks/workflow-builder/workflow-builder.ts";
import type { Actor, RequestContext } from "../../core/plugin.ts";

import {
  durationMs,
  isGraphRecord,
  topologicalOrder,
  validateGraph,
  type WorkflowGraph,
  type WorkflowGraphEdge,
  type WorkflowGraphNode,
} from "../../blocks/workflow-builder/graph.ts";
import {
  contextAttributes,
  runForKey,
  WORKFLOW_ATTRIBUTES,
  type WorkflowFn,
} from "../workflow-sdk.ts";

/** The env flag the Workflow SDK reads before it starts or runs dynamic source. */
export const DYNAMIC_WORKFLOWS_ENV = "WORKFLOW_EXPERIMENTAL_DYNAMIC_WORKFLOWS";

/** The Workflow SDK's limit on dynamic source. */
export const DYNAMIC_SOURCE_MAX_BYTES: number = 128 * 1024;

/** A graph compiled to Workflow SDK dynamic source. */
export interface CompiledGraph {
  readonly engine: "workflow-sdk";
  readonly format: 1;
  /** The workflow function's name in `source`. */
  readonly exportName: string;
  /** `async function workflow(input, meta)`, bound to `steps`, `sleep` and `createHook`. */
  readonly source: string;
  /** The step each `steps.<alias>` call runs, by alias (one alias per step node). */
  readonly aliases: Readonly<Record<string, string>>;
}

/** The second argument of a compiled or static run. */
export interface GraphRunMeta {
  /** Approval hooks use `<runKey>:<node>` as their token. */
  readonly runKey: string;
  readonly definition: string;
  readonly version: number;
}

const EXPORT_NAME = "workflow";

const literal = (value: unknown): string => JSON.stringify(value ?? null);

const aliasOf = (node: WorkflowGraphNode, index: number): string =>
  `n${index}_${node.id.replaceAll(/[^A-Za-z0-9_]/g, "_").slice(0, 40)}`;

const RUNTIME = `  const results = {};
  const ran = Object.create(null);
  const runKey = meta !== null && typeof meta === "object" && typeof meta.runKey === "string" ? meta.runKey : "";
  function read(path) {
    const parts = path.split(".");
    let value = parts[0] === "input" ? input : results;
    for (let i = 1; i < parts.length; i++) {
      if (Array.isArray(value)) value = value[Number(parts[i])];
      else if (value !== null && typeof value === "object") value = value[parts[i]];
      else return undefined;
    }
    return value;
  }
  function same(a, b) {
    return JSON.stringify(a) === JSON.stringify(b);
  }
  function test(c) {
    const actual = read(c.path);
    switch (c.op) {
      case "equals": return same(actual, c.value);
      case "notEquals": return !same(actual, c.value);
      case "exists": return actual !== undefined && actual !== null;
      case "truthy": return Boolean(actual);
      case "greaterThan": return typeof actual === "number" && typeof c.value === "number" && actual > c.value;
      case "lessThan": return typeof actual === "number" && typeof c.value === "number" && actual < c.value;
      case "contains": return typeof actual === "string" ? typeof c.value === "string" && actual.includes(c.value) : Array.isArray(actual) && actual.some((item) => same(item, c.value));
      default: return false;
    }
  }
  function took(source, branch) {
    return source in ran && (branch === null || String(ran[source]) === branch);
  }
`;

function nodeBody(node: WorkflowGraphNode, alias: string | undefined): string {
  const id = literal(node.id);
  switch (node.kind) {
    case "trigger": {
      return `results[${id}] = input;\n    ran[${id}] = true;`;
    }
    case "step": {
      return `const output = await steps.${alias ?? ""}({ node: ${id}, step: ${literal(node.step)}, config: ${literal(node.config ?? {})}, input, results: Object.assign({}, results), runKey });
    results[${id}] = output === undefined ? null : output;
    ran[${id}] = true;`;
    }
    case "sleep": {
      return `await sleep(${literal(durationMs(node.config?.["duration"]))});
    results[${id}] = null;
    ran[${id}] = true;`;
    }
    case "approval": {
      return `const payload = await createHook({ token: runKey + ":" + ${id} });
    results[${id}] = payload === undefined ? null : payload;
    ran[${id}] = !(payload !== null && typeof payload === "object" && !Array.isArray(payload) && payload.approved === false);`;
    }
    case "condition": {
      return `const outcome = test(${literal(node.config ?? {})});
    results[${id}] = outcome;
    ran[${id}] = outcome;`;
    }
    default: {
      const unknown: never = node.kind;
      throw new TypeError(
        `workflow-builder: unknown node kind ${String(unknown)}`,
      );
    }
  }
}

const guard = (edges: readonly WorkflowGraphEdge[]): string =>
  edges
    .map(
      (edge) =>
        `took(${literal(edge.source)}, ${edge.branch === undefined ? "null" : literal(edge.branch)})`,
    )
    .join(" || ");

/**
 * Compiles a graph to Workflow SDK dynamic source: plain JavaScript that
 * calls each step node through its own alias, sleeps with `sleep` and waits
 * on approvals with `createHook({ token: "<runKey>:<node>" })`. It runs the
 * same way `executeGraph` does. Throws when the graph is invalid or the
 * source is over 128 KiB. Pass it as `compile` to `createBuilder`.
 */
export function compileGraph(graph: WorkflowGraph): CompiledGraph {
  const errors = validateGraph(graph);
  if (errors.length > 0) {
    throw new TypeError(`workflow-builder: ${errors.join("; ")}`);
  }
  const order = topologicalOrder(graph) ?? [];
  const incoming = new Map<string, WorkflowGraphEdge[]>();
  for (const edge of graph.edges) {
    incoming.set(edge.target, [...(incoming.get(edge.target) ?? []), edge]);
  }
  const aliases: Record<string, string> = {};
  const blocks = order.map((node, index) => {
    let alias: string | undefined;
    if (node.kind === "step") {
      alias = aliasOf(node, index);
      aliases[alias] = node.step ?? "";
    }
    const body = nodeBody(node, alias);
    const comment = `  // ${node.kind} ${JSON.stringify(node.id).slice(1, -1).replaceAll("*/", "* /")}`;
    if (node.kind === "trigger") return `${comment}\n  {\n    ${body}\n  }`;
    return `${comment}\n  if (${guard(incoming.get(node.id) ?? [])}) {\n    ${body}\n  }`;
  });
  const source = `async function ${EXPORT_NAME}(input, meta) {
  "use workflow";
${RUNTIME}
${blocks.join("\n")}
  return Object.assign({}, results);
}
`;
  const bytes = new TextEncoder().encode(source).length;
  if (bytes > DYNAMIC_SOURCE_MAX_BYTES) {
    throw new RangeError(
      `workflow-builder: the compiled source is ${bytes} bytes; dynamic workflows take at most ${DYNAMIC_SOURCE_MAX_BYTES}`,
    );
  }
  return {
    engine: "workflow-sdk",
    format: 1,
    exportName: EXPORT_NAME,
    source,
    aliases,
  };
}

/** `value` as a compiled graph, or `undefined` when it isn't one. */
export function compiledGraphOf(value: unknown): CompiledGraph | undefined {
  if (
    !isGraphRecord(value) ||
    value["engine"] !== "workflow-sdk" ||
    value["format"] !== 1 ||
    typeof value["source"] !== "string" ||
    typeof value["exportName"] !== "string" ||
    !isGraphRecord(value["aliases"])
  ) {
    return undefined;
  }
  const aliases: Record<string, string> = {};
  for (const [alias, step] of Object.entries(value["aliases"])) {
    if (typeof step !== "string") return undefined;
    aliases[alias] = step;
  }
  return {
    engine: "workflow-sdk",
    format: 1,
    exportName: value["exportName"],
    source: value["source"],
    aliases,
  };
}

/** A step a graph can call: a `"use step"` function, or `{ stepId }`. */
export type GraphStep =
  | ((call: GraphStepCall) => Promise<unknown>)
  | { readonly stepId: string };

export interface GraphStarterOptions {
  /** The library's step functions by step name; each takes a `GraphStepCall`. */
  readonly steps: Readonly<Record<string, GraphStep>>;
  /**
   * The static executor: a `"use workflow"` function that calls
   * `executeGraph(graph, input, runtime)`. Runs start with it when dynamic
   * workflows are off.
   */
  readonly executor?: WorkflowFn<[WorkflowGraph, unknown, GraphRunMeta]>;
  /** Whether to start dynamic source; defaults to `WORKFLOW_EXPERIMENTAL_DYNAMIC_WORKFLOWS`. */
  readonly dynamic?: boolean;
  /** The World to look idempotency keys up in. Defaults to the configured one. */
  readonly world?: World;
}

const dynamicEnabled = (): boolean => {
  // SAFETY: process is optional on WinterTC runtimes; every property read is guarded.
  const runtime = globalThis as {
    process?: { env?: Record<string, string | undefined> };
  };
  const raw = runtime.process?.env?.[DYNAMIC_WORKFLOWS_ENV];
  return raw === "1" || raw?.toLowerCase() === "true";
};

function contextOf(call: BuilderStartCall): RequestContext {
  const actor: Actor | undefined =
    call.actor === undefined ? undefined : { id: call.actor, kind: "user" };
  return {
    ...(actor === undefined ? {} : { actor }),
    ...(call.tenant === undefined ? {} : { tenant: call.tenant }),
  };
}

/**
 * The `start` for `createBuilder`: starts the published version as dynamic
 * source when dynamic workflows are on (compiling it again when the stored
 * form is missing), and through `executor` otherwise. Runs carry
 * `bs.tenant`, `bs.actor`, `bs.definition`, `bs.version` and `bs.key`, and
 * a repeated key returns the first run.
 */
export function graphStarter(options: GraphStarterOptions): BuilderStarter {
  return async (call) => {
    const key = call.idempotencyKey;
    const existing = await runForKey(key, options.world);
    if (existing !== undefined) return existing;
    const graph = call.version.graph ?? { nodes: [], edges: [] };
    const meta: GraphRunMeta = {
      runKey: key,
      definition: call.definition.id,
      version: call.version.version,
    };
    const startOptions = {
      attributes: {
        ...contextAttributes(contextOf(call)),
        [WORKFLOW_ATTRIBUTES.definition]: call.definition.id,
        [WORKFLOW_ATTRIBUTES.version]: String(call.version.version),
        [WORKFLOW_ATTRIBUTES.key]: key,
      },
      ...(options.world === undefined ? {} : { world: options.world }),
    };
    if (options.dynamic ?? dynamicEnabled()) {
      const compiled =
        compiledGraphOf(call.version.compiled) ?? compileGraph(graph);
      const steps: Record<string, GraphStep> = {};
      for (const [alias, name] of Object.entries(compiled.aliases)) {
        const step = options.steps[name];
        if (step === undefined) {
          throw new Error(
            `better-supabase: the graph uses step "${name}", which was not passed to graphStarter`,
          );
        }
        steps[alias] = step;
      }
      const run = await start(compiled.source, [call.input, meta], {
        ...startOptions,
        experimental_dynamic: { steps, exportName: compiled.exportName },
      });
      return run.runId;
    }
    if (options.executor === undefined) {
      throw new Error(
        `better-supabase: dynamic workflows are off (${DYNAMIC_WORKFLOWS_ENV}); pass an executor to graphStarter`,
      );
    }
    const run = await start(
      options.executor,
      [graph, call.input, meta],
      startOptions,
    );
    return run.runId;
  };
}

/** Where `nodeRunReporter` writes: `builder.nodeRuns` from `createBuilder`. */
export interface NodeRunSink {
  record(input: NodeRunRecord): PromiseLike<unknown>;
}

/**
 * Wraps a step so it records its node in `workflow_node_runs`: `running`
 * with the attempt when it starts, then `completed` with its output or
 * `failed` with the error. Call the result inside a `"use step"` function;
 * a failed record never fails the step.
 *
 * ```ts
 * const report = nodeRunReporter(serviceBuilder.nodeRuns);
 * export async function sendEmail(call: GraphStepCall) {
 *   "use step";
 *   return report(call, () => email.send(call.config));
 * }
 * ```
 */
export function nodeRunReporter(
  sink: NodeRunSink,
): <T>(call: GraphStepCall, run: () => Promise<T>) => Promise<T> {
  const record = async (input: NodeRunRecord): Promise<void> => {
    try {
      await sink.record(input);
    } catch {
      // The run's own state is the source of truth; a lost status is shown as stale.
    }
  };
  return async (call, run) => {
    const runId = getWorkflowMetadata().workflowRunId;
    const attempt = getStepMetadata().attempt;
    await record({ run: runId, node: call.node, status: "running", attempt });
    try {
      const output = await run();
      await record({
        run: runId,
        node: call.node,
        status: "completed",
        attempt,
        output,
      });
      return output;
    } catch (cause) {
      await record({
        run: runId,
        node: call.node,
        status: "failed",
        attempt,
        error: cause instanceof Error ? cause.message : String(cause),
      });
      throw cause;
    }
  };
}
