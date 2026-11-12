import type {
  WorkflowGraph,
  WorkflowGraphEdge,
  WorkflowGraphNode,
  WorkflowNodeKindRow,
  WorkflowStepInfo,
} from "better-supabase/blocks/workflow-editor";

import { validateGraph } from "better-supabase/blocks/workflow-editor";
import * as v from "valibot";

import type { JsonObject, JsonValue } from "./config-templates";

import { JsonObjectSchema, templatePaths } from "./config-templates";

/** The pure parts of the editor: palette, history, layout, clipboard and checks. */

/** A node's config as JSON; a config that is not JSON reads as empty. */
const configOf = (node: Pick<WorkflowGraphNode, "config">): JsonObject =>
  v.parse(v.fallback(JsonObjectSchema, {}), node.config);

// ---------------------------------------------------------------- palette

export type PaletteGroup = "triggers" | "actions" | "logic" | "people" | "ai";

export interface PaletteEntry {
  /** Unique in the palette: the kind, or `step:<name>`. */
  readonly id: string;
  readonly kind: string;
  readonly step?: string | undefined;
  readonly title: string;
  readonly description: string;
  readonly group: PaletteGroup;
  /** JSON Schema of the node's config; the inspector form is built from it. */
  readonly schema: JsonObject;
  readonly branches: boolean;
  readonly credentialKind?: string | undefined;
}

const TRIGGER_SCHEMA = {
  type: "object",
  properties: {
    trigger: {
      type: "string",
      title: "Starts when",
      enum: ["manual", "schedule", "event", "webhook"],
      default: "manual",
    },
    cron: { type: "string", title: "Schedule (cron)" },
    event: { type: "string", title: "Event type" },
  },
} satisfies JsonObject;

const BUILT_IN: readonly PaletteEntry[] = [
  {
    id: "trigger",
    kind: "trigger",
    title: "Trigger",
    description:
      "Where a run starts: by hand, on a schedule, on an event or by webhook.",
    group: "triggers",
    schema: TRIGGER_SCHEMA,
    branches: false,
  },
  {
    id: "condition",
    kind: "condition",
    title: "Condition",
    description: "Takes the true or false branch from a value of the run.",
    group: "logic",
    branches: true,
    schema: {
      type: "object",
      properties: {
        path: {
          type: "string",
          title: "Path",
          description: "Such as results.summarize.words.",
          "x-mono": true,
        },
        op: {
          type: "string",
          title: "Operator",
          enum: [
            "equals",
            "notEquals",
            "exists",
            "truthy",
            "greaterThan",
            "lessThan",
            "contains",
          ],
          default: "equals",
        },
        value: {
          type: "string",
          title: "Value",
          "x-scalar": true,
          "x-mono": true,
        },
      },
      required: ["path"],
    },
  },
  {
    id: "sleep",
    kind: "sleep",
    title: "Wait",
    description: "Pauses the run for a duration such as 30s, 5m or 1d.",
    group: "logic",
    branches: false,
    schema: {
      type: "object",
      properties: {
        duration: {
          type: "string",
          title: "Duration",
          default: "1m",
          pattern: "^\\d+(ms|s|m|h|d)$",
        },
      },
      required: ["duration"],
    },
  },
  {
    id: "approval",
    kind: "approval",
    title: "Approval",
    description:
      "Waits for a member to approve or reject; the branches follow the decision.",
    group: "people",
    branches: true,
    schema: { type: "object", properties: {} },
  },
];

const groupOf = (kind: string): PaletteGroup => {
  switch (kind) {
    case "human-task": {
      return "people";
    }

    case "ai-step": {
      return "ai";
    }

    default: {
      return "logic";
    }
  }
};

/**
 * The palette from the node kind registry (ADR 0126) and the step library: the
 * five built-in kinds, then each registered kind, then each library step as an
 * action.
 */
export function buildPalette(
  steps: readonly WorkflowStepInfo[],
  kinds: readonly WorkflowNodeKindRow[],
): readonly PaletteEntry[] {
  const registered = kinds.map((row): PaletteEntry => ({
    id: row.kind,
    kind: row.kind,
    title: row.title,
    description: row.description ?? "",
    group: groupOf(row.kind),
    schema: v.parse(v.fallback(JsonObjectSchema, {}), row.configSchema),
    branches: row.branches,
  }));

  const actions = steps.map((step): PaletteEntry => ({
    id: `step:${step.name}`,
    kind: "step",
    step: step.name,
    title: step.title,
    description: step.description ?? "",
    group: "actions",
    schema: v.parse(v.fallback(JsonObjectSchema, {}), step.inputSchema ?? {}),
    branches: false,
    credentialKind: step.credentialKind,
  }));

  return [...BUILT_IN, ...registered, ...actions];
}

/** The palette entry a graph node was made from. */
export function entryOf(
  palette: readonly PaletteEntry[],
  node: { readonly kind: string; readonly step?: string | undefined },
): PaletteEntry | undefined {
  return palette.find((entry) =>
    node.kind === "step"
      ? entry.kind === "step" && entry.step === node.step
      : entry.kind === node.kind,
  );
}

/** The config a new node of `entry` starts with: the schema's defaults. */
export function defaultConfig(entry: PaletteEntry): JsonObject {
  const properties = v.safeParse(JsonObjectSchema, entry.schema["properties"]);
  const config: JsonObject = {};

  if (!properties.success) {
    return config;
  }

  for (const [key, field] of Object.entries(properties.output)) {
    const parsed = v.safeParse(JsonObjectSchema, field);

    if (parsed.success && parsed.output["default"] !== undefined) {
      config[key] = parsed.output["default"];
    }
  }

  return config;
}

/** A node id from `base` that no node of the graph uses yet. */
export function freshId(base: string, taken: ReadonlySet<string>): string {
  const slug =
    base
      .replaceAll(/[^a-z0-9]+/giu, "-")
      .replaceAll(/^-|-$/gu, "")
      .toLowerCase() || "node";

  if (!taken.has(slug)) {
    return slug;
  }

  let n = 2;

  while (taken.has(`${slug}-${n}`)) {
    n += 1;
  }

  return `${slug}-${n}`;
}

// ---------------------------------------------------------------- history

/** Past and future snapshots of the graph for undo and redo. */
export interface History {
  readonly past: readonly WorkflowGraph[];
  readonly future: readonly WorkflowGraph[];
}

export const EMPTY_HISTORY: History = { past: [], future: [] };

const HISTORY_LIMIT = 100;

/** Records `before` as an undo step; a new change drops the redo steps. */
export function recordHistory(
  history: History,
  before: WorkflowGraph,
): History {
  return { past: [...history.past, before].slice(-HISTORY_LIMIT), future: [] };
}

export interface HistoryStep {
  readonly history: History;
  readonly graph: WorkflowGraph;
}

export function undoHistory(
  history: History,
  current: WorkflowGraph,
): HistoryStep | undefined {
  const graph = history.past.at(-1);

  return graph === undefined
    ? undefined
    : {
        graph,
        history: {
          past: history.past.slice(0, -1),
          future: [current, ...history.future],
        },
      };
}

export function redoHistory(
  history: History,
  current: WorkflowGraph,
): HistoryStep | undefined {
  const [graph, ...future] = history.future;

  return graph === undefined
    ? undefined
    : { graph, history: { past: [...history.past, current], future } };
}

// ----------------------------------------------------------------- layout

/** Where the layout puts a node. */
export interface Placed {
  readonly x: number;
  readonly y: number;
}

const COLUMN = 280;
const ROW = 150;

/**
 * A layered layout: each node sits one row below its deepest parent, and the
 * nodes of a row are ordered by the average column of their parents so edges
 * cross less. Returns a position by node id, centered on x 0.
 */
export function autoLayout(graph: WorkflowGraph): ReadonlyMap<string, Placed> {
  const parents = new Map<string, string[]>();

  for (const node of graph.nodes) {
    parents.set(node.id, []);
  }

  for (const edge of graph.edges) {
    parents.get(edge.target)?.push(edge.source);
  }

  const depth = new Map<string, number>();

  const depthOf = (id: string, trail: ReadonlySet<string>): number => {
    const known = depth.get(id);

    if (known !== undefined) {
      return known;
    }

    if (trail.has(id)) {
      return 0;
    }

    const next = new Set(trail).add(id);

    const level = Math.max(
      -1,
      ...(parents.get(id) ?? []).map((parent) => depthOf(parent, next)),
    );

    depth.set(id, level + 1);

    return level + 1;
  };

  for (const node of graph.nodes) {
    depthOf(node.id, new Set());
  }

  const rows = new Map<number, string[]>();

  for (const node of graph.nodes) {
    const level = depth.get(node.id) ?? 0;
    rows.set(level, [...(rows.get(level) ?? []), node.id]);
  }

  const column = new Map<string, number>();
  const positions = new Map<string, Placed>();

  for (const level of [...rows.keys()].toSorted((a, b) => a - b)) {
    const ids = rows.get(level) ?? [];

    const average = (id: string): number => {
      const columns = (parents.get(id) ?? []).flatMap((parent) => {
        const value = column.get(parent);

        return value === undefined ? [] : [value];
      });

      return columns.length === 0
        ? 0
        : columns.reduce((sum, value) => sum + value, 0) / columns.length;
    };

    const ordered = ids.toSorted((a, b) => average(a) - average(b));
    const offset = ((ordered.length - 1) * COLUMN) / 2;

    for (const [index, id] of ordered.entries()) {
      const x = index * COLUMN - offset;
      column.set(id, x);
      positions.set(id, { x, y: level * ROW });
    }
  }

  return positions;
}

// -------------------------------------------------------------- clipboard

/** The nodes and the edges between them, as copied from the canvas. */
export interface Clipboard {
  readonly nodes: readonly WorkflowGraphNode[];
  readonly edges: readonly WorkflowGraphEdge[];
}

/** The selected nodes (never the trigger) and the edges inside the selection. */
export function copySelection(
  graph: WorkflowGraph,
  selected: ReadonlySet<string>,
): Clipboard {
  const nodes = graph.nodes.filter(
    (node) => selected.has(node.id) && node.kind !== "trigger",
  );

  const ids = new Set(nodes.map((node) => node.id));

  return {
    nodes,
    edges: graph.edges.filter(
      (edge) => ids.has(edge.source) && ids.has(edge.target),
    ),
  };
}

const PASTE_OFFSET = 48;

/** A pasted copy with fresh node and edge ids, moved down and to the right. */
export function pasteClipboard(
  clipboard: Clipboard,
  graph: WorkflowGraph,
  edgeId: () => string,
): Clipboard {
  const taken = new Set(graph.nodes.map((node) => node.id));
  const renamed = new Map<string, string>();

  const nodes = clipboard.nodes.map((node): WorkflowGraphNode => {
    const id = freshId(node.id.replace(/-\d+$/u, ""), taken);
    taken.add(id);
    renamed.set(node.id, id);

    return {
      ...node,
      id,
      position: {
        x: (node.position?.x ?? 0) + PASTE_OFFSET,
        y: (node.position?.y ?? 0) + PASTE_OFFSET,
      },
    };
  });

  const edges = clipboard.edges.flatMap((edge): WorkflowGraphEdge[] => {
    const source = renamed.get(edge.source);
    const target = renamed.get(edge.target);

    return source === undefined || target === undefined
      ? []
      : [{ ...edge, id: edgeId(), source, target }];
  });

  return { nodes, edges };
}

// ------------------------------------------------------------ data picker

/** The nodes that run before `nodeId`: everything it can read results from. */
function upstreamOf(graph: WorkflowGraph, nodeId: string): readonly string[] {
  const parents = new Map<string, string[]>();

  for (const edge of graph.edges) {
    parents.set(edge.target, [
      ...(parents.get(edge.target) ?? []),
      edge.source,
    ]);
  }

  const found = new Set<string>();
  const queue = [...(parents.get(nodeId) ?? [])];

  while (queue.length > 0) {
    const id = queue.pop();

    if (id === undefined || found.has(id) || id === nodeId) {
      continue;
    }

    found.add(id);
    queue.push(...(parents.get(id) ?? []));
  }

  return [...found];
}

const kindOutputs = (kind: string): readonly string[] => {
  switch (kind) {
    case "ai-step": {
      return ["text", "model"];
    }

    case "sub-workflow": {
      return ["runId"];
    }

    case "human-task": {
      return ["assignee", "title", "dueInDays"];
    }

    case "approval": {
      return ["approved"];
    }

    default: {
      return [];
    }
  }
};

/** The field names a node's output is known to have. */
function outputFields(
  node: WorkflowGraphNode,
  steps: readonly WorkflowStepInfo[],
): readonly string[] {
  if (node.kind === "step") {
    const properties = v.safeParse(
      JsonObjectSchema,
      steps.find((step) => step.name === node.step)?.outputSchema?.[
        "properties"
      ],
    );

    return properties.success ? Object.keys(properties.output) : [];
  }

  return kindOutputs(node.kind);
}

export interface PickerGroup {
  readonly id: string;
  readonly label: string;
  readonly paths: readonly string[];
}

/**
 * What a node's data picker offers: the run's input, then each earlier node
 * with its output and the output's known fields.
 */
export function pickerGroups(
  graph: WorkflowGraph,
  nodeId: string,
  steps: readonly WorkflowStepInfo[],
): readonly PickerGroup[] {
  const before = new Set(upstreamOf(graph, nodeId));

  const groups: PickerGroup[] = [
    { id: "input", label: "Run input", paths: ["input", "input.text"] },
  ];

  for (const node of graph.nodes) {
    if (!before.has(node.id) || node.kind === "trigger") {
      continue;
    }

    groups.push({
      id: node.id,
      label: node.label ?? node.id,
      paths: [
        `results.${node.id}`,
        ...outputFields(node, steps).map(
          (field) => `results.${node.id}.${field}`,
        ),
      ],
    });
  }

  return groups;
}

// ------------------------------------------------------------- validation

export interface EditorIssue {
  readonly severity: "error" | "warning";
  readonly message: string;
  /** The node the issue is about, when there is one. */
  readonly node?: string | undefined;
}

const hasValue = (value: JsonValue | undefined): boolean =>
  value !== undefined &&
  value !== null &&
  !(v.is(v.string(), value) && value.trim() === "") &&
  !(Array.isArray(value) && value.length === 0);

const requiredOf = (schema: JsonObject): readonly string[] =>
  v.parse(v.fallback(v.array(v.string()), []), schema["required"]);

const nodeIn = (graph: WorkflowGraph, message: string): string | undefined =>
  graph.nodes
    .map((node) => node.id)
    .filter((id) => message.includes(id))
    .toSorted((a, b) => b.length - a.length)[0];

/**
 * Everything wrong with the graph before it can publish. The errors are what
 * `validateGraph` and the schemas of the node kinds refuse; the warnings are
 * what would run but probably isn't meant: a node nothing reaches, a branching
 * node with one branch, a mapping that reads a node that has not run yet.
 */
export function validateEditor(
  graph: WorkflowGraph,
  palette: readonly PaletteEntry[],
  steps: readonly WorkflowStepInfo[],
  kinds: readonly WorkflowNodeKindRow[],
): readonly EditorIssue[] {
  const issues: EditorIssue[] = [];

  for (const message of validateGraph(graph, {
    steps: steps.map((step) => step.name),
    nodes: kinds.map((row) => ({ kind: row.kind, branches: row.branches })),
  })) {
    issues.push({ severity: "error", message, node: nodeIn(graph, message) });
  }

  const reached = new Set<string>();
  const outgoing = new Map<string, WorkflowGraphEdge[]>();

  for (const edge of graph.edges) {
    outgoing.set(edge.source, [...(outgoing.get(edge.source) ?? []), edge]);
  }

  const queue = graph.nodes
    .filter((node) => node.kind === "trigger")
    .map((node) => node.id);

  while (queue.length > 0) {
    const id = queue.pop();

    if (id === undefined || reached.has(id)) {
      continue;
    }

    reached.add(id);
    queue.push(...(outgoing.get(id) ?? []).map((edge) => edge.target));
  }

  for (const node of graph.nodes) {
    const label = node.label ?? node.id;
    const entry = entryOf(palette, node);
    const config = configOf(node);

    for (const key of requiredOf(entry?.schema ?? {})) {
      if (!hasValue(config[key])) {
        issues.push({
          severity: "error",
          node: node.id,
          message: `${label}: ${key} is required`,
        });
      }
    }

    if (node.kind !== "trigger" && !reached.has(node.id)) {
      issues.push({
        severity: "warning",
        node: node.id,
        message: `${label} is not reached from a trigger, so it never runs`,
      });
    }

    if (entry?.branches === true) {
      const branches = new Set(
        (outgoing.get(node.id) ?? []).flatMap((edge) =>
          edge.branch === undefined ? [] : [edge.branch],
        ),
      );

      if (branches.size < 2) {
        issues.push({
          severity: "warning",
          node: node.id,
          message: `${label} follows only one branch; the other ends the run`,
        });
      }
    }

    const before = new Set(upstreamOf(graph, node.id));

    for (const path of templatePaths(config)) {
      const [root, id] = path.split(".");

      if (root === "results" && id !== undefined && !before.has(id)) {
        issues.push({
          severity: "error",
          node: node.id,
          message: `${label} reads ${path}, but ${id} does not run before it`,
        });
      }
    }
  }

  return issues;
}
