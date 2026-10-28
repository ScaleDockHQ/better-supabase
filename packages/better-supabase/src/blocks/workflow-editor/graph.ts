import type { ValidationIssue } from "../../core/errors.ts";
import type {
  FilterFieldInfo,
  FilterFieldType,
  FilterQuery,
} from "../../list/filter-query.ts";

import { optionalTemporal } from "../../core/temporal.ts";
import { evaluateFilterQuery } from "../../list/filter-evaluate.ts";
import { checkFilterQuery, FILTER_OPERATORS } from "../../list/filter-query.ts";

/** Kept local: the static executor runs this file inside the workflow VM. */
export const isGraphRecord = (
  value: unknown,
): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/** The node kinds every graph may use. */
export type WorkflowBuiltinNodeKind =
  | "trigger"
  | "step"
  | "sleep"
  | "approval"
  | "condition";

/** A built-in kind, or the app's own kind from `defineNodeKind`. */
export type WorkflowNodeKind = WorkflowBuiltinNodeKind | (string & {});

export const WORKFLOW_BUILTIN_NODE_KINDS: readonly WorkflowBuiltinNodeKind[] = [
  "trigger",
  "step",
  "sleep",
  "approval",
  "condition",
];

/** Whether `kind` is one of the built-in node kinds. */
export const isBuiltinNodeKind = (
  kind: string,
): kind is WorkflowBuiltinNodeKind =>
  WORKFLOW_BUILTIN_NODE_KINDS.some((known) => known === kind);

/**
 * The shape of an app's own node kind; `workflow_node_kinds` checks the same
 * pattern.
 */
export const NODE_KIND_PATTERN: RegExp = /^[a-z][a-z0-9_.-]{0,62}$/;

/**
 * What validation needs to know about an app's own node kind: `defineNodeKind`
 * returns it.
 */
export interface WorkflowNodeKindInfo {
  readonly kind: string;
  /** Whether its edges take a `true` or `false` branch on its output. */
  readonly branches?: boolean;
  /** Problems with a node of this kind, as messages; empty when it may run. */
  readonly validate?: (node: WorkflowGraphNode) => readonly string[];
}

export type WorkflowConditionOperator =
  | "equals"
  | "notEquals"
  | "exists"
  | "truthy"
  | "greaterThan"
  | "lessThan"
  | "contains";

const OPERATORS: readonly WorkflowConditionOperator[] = [
  "equals",
  "notEquals",
  "exists",
  "truthy",
  "greaterThan",
  "lessThan",
  "contains",
];

/**
 * A test on the run's data. `path` starts at `input` (the trigger's input),
 * `results` (each node's output by node id, e.g. `results.lookup.plan`) or
 * `subject` (the record the run belongs to: `subject.type`, `subject.id`).
 */
export interface WorkflowCondition {
  readonly path: string;
  readonly op: WorkflowConditionOperator;
  readonly value?: unknown;
}

/**
 * A field a filter tests: `id` is the dotted path it reads, such as
 * `input.amount`.
 */
export interface WorkflowFilterField {
  readonly id: string;
  readonly type: FilterFieldType;
  /**
   * The Postgres type the value compares as. Only dates use it: `date` compares
   * calendar days, `timestamptz` (the default) instants.
   */
  readonly columnType?: string;
}

/**
 * A `FilterQuery` tree (the rule builder's and the list filters' format) over
 * the fields its rules name.
 */
export interface WorkflowFilterCondition {
  readonly filter: FilterQuery;
  readonly fields: readonly WorkflowFilterField[];
}

/** What a `condition` node tests: one comparison or a filter tree. */
export type WorkflowNodeCondition = WorkflowCondition | WorkflowFilterCondition;

/**
 * One node of a graph. A `step` node calls the library step `step` with its
 * `config`; a `sleep` node waits `config.duration` (milliseconds, or `30s`,
 * `5m`, `2h`, `1d`); an `approval` node waits for its hook to be resumed; a
 * `condition` node tests `config`: a `WorkflowCondition`, or a
 * `WorkflowFilterCondition` (`{ filter, fields }`).
 */
export interface WorkflowGraphNode {
  readonly id: string;
  readonly kind: WorkflowNodeKind;
  readonly label?: string;
  readonly step?: string;
  readonly config?: Readonly<Record<string, unknown>>;
  /** Where the canvas draws it; the engines ignore it. */
  readonly position?: { readonly x: number; readonly y: number };
}

/**
 * An edge runs its target after its source. From a `condition` or an `approval`
 * node, `branch` picks the outcome it follows (an approval is `true` unless its
 * payload has `approved: false`).
 */
export interface WorkflowGraphEdge {
  readonly id: string;
  readonly source: string;
  readonly target: string;
  readonly branch?: "true" | "false";
}

/** The engine-neutral graph a workflow version stores. */
export interface WorkflowGraph {
  readonly nodes: readonly WorkflowGraphNode[];
  readonly edges: readonly WorkflowGraphEdge[];
}

const DURATION = /^(\d+)(ms|s|m|h|d)$/;

const UNIT_MS: ReadonlyMap<string, number> = new Map([
  ["ms", 1],
  ["s", 1000],
  ["m", 60_000],
  ["h", 3_600_000],
  ["d", 86_400_000],
]);

/** A sleep duration in milliseconds; `undefined` when `value` isn't one. */
export function durationMs(value: unknown): number | undefined {
  if (typeof value === "number") {
    return Number.isFinite(value) && value > 0 ? Math.round(value) : undefined;
  }

  if (typeof value !== "string") {
    return undefined;
  }

  const match = DURATION.exec(value.trim());

  if (match === null) {
    return undefined;
  }

  const factor = UNIT_MS.get(match[2] ?? "");
  const ms = Number(match[1]) * (factor ?? 0);

  return ms > 0 ? ms : undefined;
}

const CONDITION_PATH = /^(input|results|subject)(\.[^.]+)*$/;

const FILTER_LIMITS = {
  maxDepth: 4,
  maxRules: 50,
  maxValueLength: 10_000,
  maxValues: 100,
} as const;

const MAX_FILTER_FIELDS = 100;

const isFilterType = (value: unknown): value is FilterFieldType =>
  typeof value === "string" && Object.hasOwn(FILTER_OPERATORS, value);

function filterFieldOf(
  value: unknown,
  pattern: RegExp,
): WorkflowFilterField | undefined {
  if (!isGraphRecord(value)) {
    return undefined;
  }

  const { id, type, columnType } = value;

  if (
    typeof id !== "string" ||
    !pattern.test(id) ||
    !isFilterType(type) ||
    (columnType !== undefined && typeof columnType !== "string")
  ) {
    return undefined;
  }

  return { id, type, ...(columnType === undefined ? {} : { columnType }) };
}

const columnTypeOf = (field: WorkflowFilterField): string =>
  field.columnType ?? (field.type === "date" ? "timestamptz" : "text");

function fieldInfoOf(field: WorkflowFilterField): FilterFieldInfo {
  return {
    id: field.id,
    type: field.type,
    column: field.id,
    columnMeta: {
      db: field.id,
      type: columnTypeOf(field),
      nullable: true,
      hasDefault: false,
    },
    label: field.id,
    operators: FILTER_OPERATORS[field.type],
  };
}

/**
 * `{ filter, fields }` as a checked filter condition whose field ids match
 * `pattern`; `undefined` when it isn't one or the tree has no finished rule.
 */
export function filterConditionOf(
  value: unknown,
  pattern: RegExp = CONDITION_PATH,
): WorkflowFilterCondition | undefined {
  if (
    !isGraphRecord(value) ||
    !Array.isArray(value["fields"]) ||
    value["fields"].length > MAX_FILTER_FIELDS
  ) {
    return undefined;
  }

  const fields: WorkflowFilterField[] = [];

  for (const entry of value["fields"]) {
    const field = filterFieldOf(entry, pattern);

    if (field === undefined) {
      return undefined;
    }

    fields.push(field);
  }

  const issues: ValidationIssue[] = [];

  const filter = checkFilterQuery(
    value["filter"],
    fields.map(fieldInfoOf),
    FILTER_LIMITS,
    issues,
  );

  return filter === undefined || issues.length > 0
    ? undefined
    : { filter, fields };
}

/**
 * Whether a filter condition holds for `record`. Relative dates resolve against
 * `Date.now()`, which the workflow runtime keeps deterministic.
 */
export function matchesFilter(
  condition: WorkflowFilterCondition,
  record: unknown,
): boolean {
  const T = optionalTemporal();

  return evaluateFilterQuery(
    condition.filter,
    record,
    condition.fields.map((field) => ({
      id: field.id,
      type: field.type,
      column: field.id,
      columnMeta: { type: columnTypeOf(field), nullable: true },
    })),
    T === undefined ? {} : { now: T.Instant.fromEpochMilliseconds(Date.now()) },
  ).matched;
}

/** The node's condition, or `undefined` when its config isn't one. */
export function conditionOf(
  node: WorkflowGraphNode,
): WorkflowNodeCondition | undefined {
  const config = node.config;

  if (config === undefined) {
    return undefined;
  }

  if (config["filter"] !== undefined) {
    return filterConditionOf(config);
  }

  const path = config["path"];
  const op = OPERATORS.find((known) => known === config["op"]);

  if (typeof path !== "string" || op === undefined) {
    return undefined;
  }

  if (!CONDITION_PATH.test(path)) {
    return undefined;
  }

  return { path, op, value: config["value"] };
}

/** The run's data a condition reads. */
export interface GraphScope {
  readonly input: unknown;
  readonly results: unknown;
  /** The record the run belongs to, when it has one. */
  readonly subject?: unknown;
}

/** Reads `path` (`input...`, `results...` or `subject...`) from the run's data. */
export function readPath(scope: GraphScope, path: string): unknown {
  const [root, ...rest] = path.split(".");

  let value: unknown =
    root === "input"
      ? scope.input
      : root === "subject"
        ? scope.subject
        : scope.results;

  for (const key of rest) {
    if (Array.isArray(value)) {
      value = value[Number(key)];
    } else if (isGraphRecord(value)) {
      value = value[key];
    } else {
      return undefined;
    }
  }

  return value;
}

/** Whether `condition` holds for the run's data. */
export function evaluateCondition(
  condition: WorkflowNodeCondition,
  scope: GraphScope,
): boolean {
  if ("filter" in condition) {
    return matchesFilter(condition, scope);
  }

  const actual = readPath(scope, condition.path);
  const expected = condition.value;

  switch (condition.op) {
    case "equals": {
      return JSON.stringify(actual) === JSON.stringify(expected);
    }

    case "notEquals": {
      return JSON.stringify(actual) !== JSON.stringify(expected);
    }

    case "exists": {
      return actual !== undefined && actual !== null;
    }

    case "truthy": {
      return Boolean(actual);
    }

    case "greaterThan": {
      return (
        typeof actual === "number" &&
        typeof expected === "number" &&
        actual > expected
      );
    }

    case "lessThan": {
      return (
        typeof actual === "number" &&
        typeof expected === "number" &&
        actual < expected
      );
    }

    case "contains": {
      if (typeof actual === "string") {
        return typeof expected === "string" && actual.includes(expected);
      }

      return (
        Array.isArray(actual) &&
        actual.some((item) => JSON.stringify(item) === JSON.stringify(expected))
      );
    }

    default: {
      const unknown: never = condition.op;
      throw new TypeError(
        `workflow-editor: unknown operator "${String(unknown)}"`,
      );
    }
  }
}

/** Whether an approval payload approves: anything but `{ approved: false }`. */
export const approved = (payload: unknown): boolean =>
  !(isGraphRecord(payload) && payload["approved"] === false);

/**
 * The nodes in an order that runs every source before its targets, keeping the
 * graph's order among independent nodes; `undefined` when edges form a cycle.
 */
export function topologicalOrder(
  graph: WorkflowGraph,
): readonly WorkflowGraphNode[] | undefined {
  const indegree = new Map(graph.nodes.map((node) => [node.id, 0]));
  const targets = new Map<string, string[]>();

  for (const edge of graph.edges) {
    if (!indegree.has(edge.source) || !indegree.has(edge.target)) {
      continue;
    }

    indegree.set(edge.target, (indegree.get(edge.target) ?? 0) + 1);
    targets.set(edge.source, [
      ...(targets.get(edge.source) ?? []),
      edge.target,
    ]);
  }

  const byId = new Map(graph.nodes.map((node) => [node.id, node]));
  const order: WorkflowGraphNode[] = [];
  const ready = graph.nodes.filter((node) => indegree.get(node.id) === 0);

  while (ready.length > 0) {
    const node = ready.shift();

    if (node === undefined) {
      break;
    }

    order.push(node);

    for (const target of targets.get(node.id) ?? []) {
      const left = (indegree.get(target) ?? 0) - 1;
      indegree.set(target, left);
      const next = byId.get(target);

      if (left === 0 && next !== undefined) {
        ready.push(next);
      }
    }
  }

  return order.length === graph.nodes.length ? order : undefined;
}

/**
 * `value` as a node, or `undefined` when its id is missing or its kind is
 * neither built in nor shaped like an app's own kind.
 */
export function nodeOf(value: unknown): WorkflowGraphNode | undefined {
  if (!isGraphRecord(value)) {
    return undefined;
  }

  const { id, kind } = value;

  if (
    typeof id !== "string" ||
    typeof kind !== "string" ||
    !(isBuiltinNodeKind(kind) || NODE_KIND_PATTERN.test(kind))
  ) {
    return undefined;
  }

  const { label, step, config, position } = value;

  return {
    id,
    kind,
    ...(typeof label === "string" ? { label } : {}),
    ...(typeof step === "string" ? { step } : {}),
    ...(isGraphRecord(config) ? { config } : {}),
    ...(isGraphRecord(position) &&
    typeof position["x"] === "number" &&
    typeof position["y"] === "number"
      ? { position: { x: position["x"], y: position["y"] } }
      : {}),
  };
}

/** `value` as an edge, or `undefined` when its ends are missing. */
export function edgeOf(value: unknown): WorkflowGraphEdge | undefined {
  if (!isGraphRecord(value)) {
    return undefined;
  }

  const { id, source, target, branch } = value;

  if (typeof source !== "string" || typeof target !== "string") {
    return undefined;
  }

  return {
    id: typeof id === "string" ? id : `${source}->${target}`,
    source,
    target,
    ...(branch === "true" || branch === "false" ? { branch } : {}),
  };
}

/**
 * Node ids reach generated source and SQL; `validate_workflow_graph` uses the
 * same pattern.
 */
const NODE_ID = /^[A-Za-z0-9_-]{1,100}$/;

const BRANCHING: ReadonlySet<string> = new Set(["condition", "approval"]);

export interface ValidateGraphOptions {
  /**
   * The step library's names: every step node must use one (`publish` checks it
   * again in SQL).
   */
  readonly steps?: Iterable<string>;
  /**
   * The app's own node kinds (`defineNodeKind`); a node of a kind that is
   * neither built in nor here is an error.
   */
  readonly nodes?: Iterable<WorkflowNodeKindInfo>;
}

/** Whether a node of `kind` branches, given the app's own kinds. */
export function branchesOn(
  kind: string,
  nodes: ReadonlyMap<string, WorkflowNodeKindInfo>,
): boolean {
  return BRANCHING.has(kind) || nodes.get(kind)?.branches === true;
}

function builtinErrors(
  node: WorkflowGraphNode,
  kind: WorkflowBuiltinNodeKind,
  library: ReadonlySet<string> | undefined,
): readonly string[] {
  const { id } = node;

  switch (kind) {
    case "trigger":
    case "approval": {
      return [];
    }

    case "step": {
      if (typeof node.step !== "string" || node.step.length === 0) {
        return [`Node ${id} names no step`];
      }

      return library !== undefined && !library.has(node.step)
        ? [
            `Node ${id} uses step ${node.step}, which is not in the step library`,
          ]
        : [];
    }

    case "sleep": {
      return durationMs(node.config?.["duration"]) === undefined
        ? [`Node ${id} has no valid duration`]
        : [];
    }

    case "condition": {
      return conditionOf(node) === undefined
        ? [`Node ${id} has no valid condition`]
        : [];
    }

    default: {
      const unknown: never = kind;

      return [`Node ${id} has an unknown kind ${String(unknown)}`];
    }
  }
}

/**
 * Problems that keep `graph` from running, as messages; empty when it can.
 * `options.steps` checks step nodes against the library and `options.nodes`
 * lists the app's own node kinds.
 */
export function validateGraph(
  graph: unknown,
  options: ValidateGraphOptions = {},
): readonly string[] {
  if (
    !isGraphRecord(graph) ||
    !Array.isArray(graph["nodes"]) ||
    !Array.isArray(graph["edges"])
  ) {
    return ["A graph has a nodes array and an edges array"];
  }

  const errors: string[] = [];

  const library =
    options.steps === undefined ? undefined : new Set(options.steps);

  const kinds = new Map(
    [...(options.nodes ?? [])].map((info) => [info.kind, info]),
  );

  const nodes = new Map<string, WorkflowGraphNode>();
  let triggers = 0;

  for (const value of graph["nodes"]) {
    const id: unknown = isGraphRecord(value) ? value["id"] : undefined;

    if (!isGraphRecord(value) || typeof id !== "string" || !NODE_ID.test(id)) {
      errors.push(
        "Every node has an id of 1 to 100 letters, digits, underscores or hyphens",
      );
      continue;
    }

    if (nodes.has(id)) {
      errors.push(`Node ${id} appears twice`);
    }

    const node = nodeOf(value);

    if (node === undefined) {
      errors.push(`Node ${id} has an unknown kind`);
      continue;
    }

    nodes.set(id, node);

    if (isBuiltinNodeKind(node.kind)) {
      triggers += node.kind === "trigger" ? 1 : 0;
      errors.push(...builtinErrors(node, node.kind, library));
      continue;
    }

    const custom = kinds.get(node.kind);

    if (custom === undefined) {
      errors.push(`Node ${id} has an unknown kind`);
    } else {
      errors.push(...(custom.validate?.(node) ?? []));
    }
  }

  if (triggers === 0) {
    errors.push("A graph has at least one trigger node");
  }

  const edgeIds = new Set<string>();
  const edges: WorkflowGraphEdge[] = [];

  for (const value of graph["edges"]) {
    const id =
      isGraphRecord(value) && typeof value["id"] === "string"
        ? value["id"]
        : "?";

    if (
      !isGraphRecord(value) ||
      typeof value["source"] !== "string" ||
      typeof value["target"] !== "string" ||
      !nodes.has(value["source"]) ||
      !nodes.has(value["target"])
    ) {
      errors.push(`Edge ${id} joins a node that does not exist`);
      continue;
    }

    if (edgeIds.has(id)) {
      errors.push(`Edge ${id} appears twice`);
    }

    edgeIds.add(id);
    const source = nodes.get(value["source"]);
    const target = nodes.get(value["target"]);
    const branch = value["branch"];

    if (branch !== undefined) {
      if (branch !== "true" && branch !== "false") {
        errors.push(`Edge ${id} has a branch other than "true" or "false"`);
      } else if (source !== undefined && !branchesOn(source.kind, kinds)) {
        errors.push(`Edge ${id} branches from a ${source.kind} node`);
      }
    }

    if (target?.kind === "trigger") {
      errors.push(`Edge ${id} leads into the trigger node`);
    }

    edges.push({ id, source: value["source"], target: value["target"] });
  }

  if (
    errors.length === 0 &&
    topologicalOrder({ nodes: [...nodes.values()], edges }) === undefined
  ) {
    errors.push("The graph has a cycle");
  }

  return errors;
}

export interface WorkflowGraphDiff {
  readonly nodes: {
    readonly added: readonly string[];
    readonly removed: readonly string[];
    /**
     * Nodes whose kind, step, label or config changed; moving one doesn't
     * count.
     */
    readonly changed: readonly string[];
  };
  readonly edges: {
    readonly added: readonly string[];
    readonly removed: readonly string[];
  };
}

const nodeContent = (node: WorkflowGraphNode): string =>
  JSON.stringify([node.kind, node.step, node.label, node.config]);

const edgeKey = (edge: WorkflowGraphEdge): string =>
  `${edge.source}->${edge.target}${edge.branch === undefined ? "" : `:${edge.branch}`}`;

/** What changed from `before` to `after`, by node id and by edge ends. */
export function diffGraphs(
  before: WorkflowGraph,
  after: WorkflowGraph,
): WorkflowGraphDiff {
  const old = new Map(before.nodes.map((node) => [node.id, node]));
  const now = new Map(after.nodes.map((node) => [node.id, node]));
  const oldEdges = new Set(before.edges.map(edgeKey));
  const newEdges = new Set(after.edges.map(edgeKey));

  return {
    nodes: {
      added: [...now.keys()].filter((id) => !old.has(id)),
      removed: [...old.keys()].filter((id) => !now.has(id)),
      changed: [...now.values()]
        .filter((node) => {
          const previous = old.get(node.id);

          return (
            previous !== undefined &&
            nodeContent(previous) !== nodeContent(node)
          );
        })
        .map((node) => node.id),
    },
    edges: {
      added: [...newEdges].filter((key) => !oldEdges.has(key)),
      removed: [...oldEdges].filter((key) => !newEdges.has(key)),
    },
  };
}

/** `value` as a graph, or an empty one when it isn't shaped like one. */
export function graphOf(value: unknown): WorkflowGraph {
  if (!isGraphRecord(value)) {
    return { nodes: [], edges: [] };
  }

  const nodes = Array.isArray(value["nodes"]) ? value["nodes"] : [];
  const edges = Array.isArray(value["edges"]) ? value["edges"] : [];

  return {
    nodes: nodes.flatMap((node) => nodeOf(node) ?? []),
    edges: edges.flatMap((edge) => edgeOf(edge) ?? []),
  };
}
