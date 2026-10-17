import type { RelationEdge } from "./relations.ts";

/** How a Gantt dependency links two bars: finish-to-start and the rest. */
export type GanttDependencyType = "FS" | "SS" | "FF" | "SF";

export interface GanttDependency {
  /** The task this one depends on. */
  readonly id: string;
  readonly type: GanttDependencyType;
  /** Days between the two ends; negative for a lead. */
  readonly lag: number;
}

const DEPENDENCY_TYPES: readonly GanttDependencyType[] = [
  "FS",
  "SS",
  "FF",
  "SF",
];

function dependencyType(value: unknown): GanttDependencyType {
  return DEPENDENCY_TYPES.find((type) => type === value) ?? "FS";
}

/**
 * Adds each task's dependencies from `blocks` edges: when A blocks B, B
 * depends on A. The edge's `data.type` and `data.lag` set the dependency
 * type (default `FS`) and lag (default 0). Edges to tasks outside the list
 * are left out.
 */
export function toGanttTasks<T extends { readonly id: string }>(
  tasks: readonly T[],
  edges: readonly RelationEdge[],
): (T & { readonly dependencies: readonly GanttDependency[] })[] {
  const ids = new Set(tasks.map((task) => task.id));
  const byTask = new Map<string, GanttDependency[]>();

  for (const edge of edges) {
    if (!ids.has(edge.source.id) || !ids.has(edge.target.id)) {
      continue;
    }

    const type = edge.data["type"];
    const lag = edge.data["lag"];
    const list = byTask.get(edge.target.id) ?? [];
    list.push({
      id: edge.source.id,
      type: dependencyType(type),
      lag: typeof lag === "number" && Number.isFinite(lag) ? lag : 0,
    });
    byTask.set(edge.target.id, list);
  }

  return tasks.map((task) => ({
    ...task,
    dependencies: byTask.get(task.id) ?? [],
  }));
}

export interface TreeItem {
  readonly name: string;
  readonly children: readonly string[];
}

/**
 * Builds the flat item map a tree view takes (`{ [id]: { name, children } }`,
 * as in Headless Tree) from `parent` edges, where the source is the child.
 * Items without a parent in the list hang under `rootId`. Children keep the
 * order of `items`.
 */
export function toTreeItems(
  items: readonly { readonly id: string; readonly name: string }[],
  edges: readonly RelationEdge[],
  options: { readonly rootId?: string; readonly rootName?: string } = {},
): Record<string, TreeItem> {
  const rootId = options.rootId ?? "root";
  const ids = new Set(items.map((item) => item.id));
  const parentOf = new Map<string, string>();

  for (const edge of edges) {
    if (ids.has(edge.source.id) && ids.has(edge.target.id)) {
      parentOf.set(edge.source.id, edge.target.id);
    }
  }

  const children = new Map<string, string[]>([[rootId, []]]);

  for (const item of items) {
    const parent = parentOf.get(item.id) ?? rootId;
    const list = children.get(parent) ?? [];
    list.push(item.id);
    children.set(parent, list);
  }

  const tree: Record<string, TreeItem> = {
    [rootId]: {
      name: options.rootName ?? "",
      children: children.get(rootId) ?? [],
    },
  };

  for (const item of items) {
    tree[item.id] = { name: item.name, children: children.get(item.id) ?? [] };
  }

  return tree;
}
