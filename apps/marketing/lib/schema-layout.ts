import type { ElkExtendedEdge, ElkNode, ElkPort } from "elkjs/lib/elk-api";

import ELK from "elkjs/lib/elk.bundled.js";

import {
  keyColumnsOf,
  type SchemaColumn,
  type SchemaData,
  type SchemaTable,
} from "./schema";

// The sizes match the node classes: w-62, h-9 header, h-6 rows, py-1 lists, h-10 external and collapsed groups.
export const NODE_WIDTH = 248;
const HEADER_HEIGHT = 36;
const ROW_HEIGHT = 24;
const LIST_PADDING = 4;
const COMPACT_HEIGHT = 40;
export const GROUP_PADDING = { top: 40, side: 16, bottom: 16 } as const;

/** The rows under a table's columns: "+N columns", "Show fewer" and "Add column". */
export type FooterRow = "more" | "less" | "add";

export interface TableRows {
  readonly columns: readonly SchemaColumn[];
  readonly footer: readonly FooterRow[];
  readonly hidden: number;
}

export interface RowOptions {
  readonly expanded: boolean;
  /** Whether the table takes new columns: app tables and the tables `extraColumns` targets. */
  readonly editable: boolean;
  /** App tables always show every column. */
  readonly app: boolean;
}

/** The soft reference columns of each table. */
export function softColumns(
  data: Pick<SchemaData, "softRefs">,
): ReadonlyMap<string, ReadonlySet<string>> {
  const byTable = new Map<string, Set<string>>();

  for (const ref of data.softRefs) {
    const columns = byTable.get(ref.from) ?? new Set<string>();
    columns.add(ref.column);
    byTable.set(ref.from, columns);
  }

  return byTable;
}

/** The columns a table node shows and the rows under them. */
export function tableRows(
  table: SchemaTable,
  soft: ReadonlySet<string> | undefined,
  options: RowOptions,
): TableRows {
  const keys = keyColumnsOf(table, soft);
  const all = options.app || options.expanded;
  const columns = all ? table.columns : keys;
  const hidden = table.columns.length - columns.length;
  const collapsible = !options.app && table.columns.length > keys.length;

  return {
    columns,
    hidden,
    footer: [
      ...(collapsible
        ? [hidden > 0 ? ("more" as const) : ("less" as const)]
        : []),
      ...(options.editable ? ["add" as const] : []),
    ],
  };
}

export function tableHeight(rows: TableRows): number {
  return (
    HEADER_HEIGHT +
    (rows.columns.length + rows.footer.length) * ROW_HEIGHT +
    LIST_PADDING * 2
  );
}

/** The y of a column row's center, from the top of the node. */
function rowCenter(index: number): number {
  return HEADER_HEIGHT + LIST_PADDING + index * ROW_HEIGHT + ROW_HEIGHT / 2;
}

export interface Point {
  readonly x: number;
  readonly y: number;
}

export interface LayoutRect extends Point {
  readonly width: number;
  readonly height: number;
}

export interface LayoutTable extends LayoutRect {
  readonly rows: TableRows;
}

export interface LayoutGroup extends LayoutRect {
  readonly id: string;
  readonly manifest: string;
  readonly members: readonly string[];
  readonly collapsed: boolean;
}

export type EdgeKind = "foreign" | "soft";

export interface LayoutEdge {
  readonly id: string;
  /** The referenced table, a Supabase table or a collapsed group. */
  readonly source: string;
  /** The column on the referenced table, or `null` for the header. */
  readonly sourceColumn: string | null;
  /** The table with the referencing column, or a collapsed group. */
  readonly target: string;
  readonly targetColumn: string | null;
  readonly kind: EdgeKind;
  readonly points: readonly Point[];
}

export interface SchemaLayout {
  readonly tables: Readonly<Record<string, LayoutTable>>;
  readonly externals: Readonly<Record<string, LayoutRect>>;
  readonly groups: readonly LayoutGroup[];
  readonly edges: readonly LayoutEdge[];
}

export interface LayoutOptions {
  readonly expanded: ReadonlySet<string>;
  readonly softRefs: boolean;
  /** Manifests drawn as one compact node. */
  readonly collapsed: ReadonlySet<string>;
  /** The tables to draw; every table when `undefined`. */
  readonly visible?: ReadonlySet<string> | undefined;
  readonly isApp: (table: SchemaTable) => boolean;
}

/**
 * An SVG path through the points with each corner rounded by up to
 * `radius`, less where the segments around it are shorter.
 */
export function roundedPath(points: readonly Point[], radius = 8): string {
  const [first, ...rest] = points;

  if (first === undefined) {
    return "";
  }

  let path = `M ${first.x} ${first.y}`;

  for (let index = 0; index < rest.length; index += 1) {
    const corner = rest[index];
    const before = points[index];
    const after = rest[index + 1];

    if (corner === undefined || before === undefined) {
      break;
    }

    if (after === undefined) {
      path += ` L ${corner.x} ${corner.y}`;
      break;
    }

    const into = Math.hypot(corner.x - before.x, corner.y - before.y);
    const out = Math.hypot(after.x - corner.x, after.y - corner.y);
    const r = Math.min(radius, into / 2, out / 2);

    if (r === 0 || into === 0 || out === 0) {
      path += ` L ${corner.x} ${corner.y}`;
      continue;
    }

    const start = {
      x: corner.x - ((corner.x - before.x) / into) * r,
      y: corner.y - ((corner.y - before.y) / into) * r,
    };

    const end = {
      x: corner.x + ((after.x - corner.x) / out) * r,
      y: corner.y + ((after.y - corner.y) / out) * r,
    };

    path += ` L ${start.x} ${start.y} Q ${corner.x} ${corner.y} ${end.x} ${end.y}`;
  }

  return path;
}

export function groupId(manifest: string): string {
  return `group:${manifest}`;
}

const HEADER = "";

function portId(
  node: string,
  column: string | null,
  side: "in" | "out",
): string {
  return `${node}:${column ?? HEADER}:${side}`;
}

interface Relation {
  readonly id: string;
  readonly from: string;
  readonly column: string;
  readonly to: string;
  readonly toColumn: string | null;
  readonly kind: EdgeKind;
}

function relationsOf(data: SchemaData, softRefs: boolean): readonly Relation[] {
  const byId = new Map(data.tables.map((table) => [table.id, table]));
  const relations: Relation[] = [];

  for (const table of data.tables) {
    for (const key of table.foreignKeys) {
      const to = `${key.target.schema}.${key.target.table}`;
      const target = byId.get(to);
      const column = key.columns[0];

      if (column !== undefined) {
        relations.push({
          id: `${table.id}.${column}->${to}`,
          from: table.id,
          column,
          to,
          toColumn: key.target.columns[0] ?? target?.primaryKey[0] ?? null,
          kind: "foreign",
        });
      }
    }
  }

  if (softRefs) {
    for (const ref of data.softRefs) {
      if (ref.to !== null) {
        relations.push({
          id: `${ref.from}.${ref.column}->${ref.to}`,
          from: ref.from,
          column: ref.column,
          to: ref.to,
          toColumn: byId.get(ref.to)?.primaryKey[0] ?? null,
          kind: "soft",
        });
      }
    }
  }

  return relations;
}

const elk = new ELK();

const ROOT_OPTIONS = {
  "elk.algorithm": "layered",
  "elk.direction": "RIGHT",
  "elk.hierarchyHandling": "INCLUDE_CHILDREN",
  "elk.edgeRouting": "ORTHOGONAL",
  "elk.layered.spacing.nodeNodeBetweenLayers": "64",
  "elk.layered.spacing.edgeNodeBetweenLayers": "24",
  "elk.spacing.nodeNode": "32",
  "elk.spacing.edgeEdge": "12",
  "elk.layered.nodePlacement.strategy": "BRANDES_KOEPF",
  "elk.separateConnectedComponents": "true",
  "elk.aspectRatio": "1.6",
  "elk.json.shapeCoords": "ROOT",
  "elk.json.edgeCoords": "ROOT",
} as const satisfies Readonly<Record<string, string>>;

const GROUP_OPTIONS = {
  "elk.padding": `[top=${GROUP_PADDING.top},left=${GROUP_PADDING.side},bottom=${GROUP_PADDING.bottom},right=${GROUP_PADDING.side}]`,
  "elk.spacing.nodeNode": "24",
} as const satisfies Readonly<Record<string, string>>;

const FIXED_PORTS = { "elk.portConstraints": "FIXED_POS" } as const;

function port(
  node: string,
  column: string | null,
  side: "in" | "out",
  y: number,
): ElkPort {
  return {
    id: portId(node, column, side),
    width: 1,
    height: 1,
    x: side === "out" ? NODE_WIDTH : -1,
    y,
    layoutOptions: { "elk.port.side": side === "out" ? "EAST" : "WEST" },
  };
}

function pointsOf(edge: ElkExtendedEdge): readonly Point[] {
  const section = edge.sections?.[0];

  return section === undefined
    ? []
    : [section.startPoint, ...(section.bendPoints ?? []), section.endPoint];
}

/** Every table in a plain grid, for when ELK fails. */
function gridLayout(
  tables: readonly SchemaTable[],
  rows: ReadonlyMap<string, TableRows>,
): SchemaLayout {
  return {
    tables: Object.fromEntries(
      tables.flatMap((table, index) => {
        const tableRowsOf = rows.get(table.id);

        return tableRowsOf === undefined
          ? []
          : [
              [
                table.id,
                {
                  x: (index % 4) * (NODE_WIDTH + 48),
                  y: Math.floor(index / 4) * 320,
                  width: NODE_WIDTH,
                  height: tableHeight(tableRowsOf),
                  rows: tableRowsOf,
                },
              ] as const,
            ];
      }),
    ),
    externals: {},
    groups: [],
    edges: [],
  };
}

/**
 * Places the tables with ELK: one compound node per block manifest, a port
 * on every column a relation uses, and orthogonal routes between them. A
 * referenced table sits to the left of the tables that reference it.
 */
export async function layoutSchema(
  data: SchemaData,
  options: LayoutOptions,
): Promise<SchemaLayout> {
  const soft = softColumns(data);

  const tables = data.tables.filter(
    (table) => options.visible === undefined || options.visible.has(table.id),
  );

  const known = new Set(tables.map((table) => table.id));
  const extra = new Set(data.extraColumns);

  const rows = new Map(
    tables.map((table) => [
      table.id,
      tableRows(table, soft.get(table.id), {
        expanded: options.expanded.has(table.id),
        app: options.isApp(table),
        editable: options.isApp(table) || extra.has(table.id),
      }),
    ]),
  );

  const manifestOf = (id: string): string => data.manifests[id] ?? id;

  const collapsedNode = (id: string): string | undefined =>
    known.has(id) && options.collapsed.has(manifestOf(id))
      ? groupId(manifestOf(id))
      : undefined;

  const allIds = new Set(data.tables.map((table) => table.id));

  const relations = relationsOf(data, options.softRefs).flatMap(
    (relation): readonly LayoutEdge[] => {
      // A hidden table's relations go with it; a table outside the schema is a Supabase one.
      if (
        !known.has(relation.from) ||
        (allIds.has(relation.to) && !known.has(relation.to))
      ) {
        return [];
      }

      const source = collapsedNode(relation.to) ?? relation.to;
      const target = collapsedNode(relation.from) ?? relation.from;

      if (source === target && source.startsWith("group:")) {
        return [];
      }

      const sourceRows = rows.get(source);
      const targetRows = rows.get(target);

      const visible = (
        list: TableRows | undefined,
        column: string | null,
      ): string | null =>
        column !== null &&
        list?.columns.some((each) => each.name === column) === true
          ? column
          : null;

      return [
        {
          id: `${source}:${relation.toColumn ?? HEADER}->${target}:${relation.column}`,
          source,
          sourceColumn: visible(sourceRows, relation.toColumn),
          target,
          targetColumn: visible(targetRows, relation.column),
          kind: relation.kind,
          points: [],
        },
      ];
    },
  );

  const edges = [...new Map(relations.map((edge) => [edge.id, edge])).values()];

  const externals = [
    ...new Set(
      edges.flatMap((edge) =>
        known.has(edge.source) || edge.source.startsWith("group:")
          ? []
          : [edge.source],
      ),
    ),
  ];

  const ports = new Map<string, Map<string, ElkPort>>();

  const addPort = (
    node: string,
    column: string | null,
    side: "in" | "out",
  ): void => {
    const list = rows.get(node);

    const index =
      column === null
        ? -1
        : (list?.columns.findIndex((each) => each.name === column) ?? -1);

    const y =
      index === -1
        ? list === undefined
          ? COMPACT_HEIGHT / 2
          : HEADER_HEIGHT / 2
        : rowCenter(index);

    const nodePorts = ports.get(node) ?? new Map<string, ElkPort>();
    nodePorts.set(portId(node, column, side), port(node, column, side, y));
    ports.set(node, nodePorts);
  };

  for (const edge of edges) {
    addPort(edge.source, edge.sourceColumn, "out");
    addPort(edge.target, edge.targetColumn, "in");
  }

  const portsOf = (node: string): ElkPort[] => [
    ...(ports.get(node)?.values() ?? []),
  ];

  const byManifest = new Map<string, SchemaTable[]>();

  for (const table of tables) {
    const list = byManifest.get(manifestOf(table.id)) ?? [];
    list.push(table);
    byManifest.set(manifestOf(table.id), list);
  }

  const graph: ElkNode = {
    id: "root",
    layoutOptions: ROOT_OPTIONS,
    children: [
      ...externals.map((id) => ({
        id,
        width: NODE_WIDTH,
        height: COMPACT_HEIGHT,
        layoutOptions: FIXED_PORTS,
        ports: portsOf(id),
      })),
      ...[...byManifest].map(([manifest, members]): ElkNode =>
        options.collapsed.has(manifest)
          ? {
              id: groupId(manifest),
              width: NODE_WIDTH,
              height: COMPACT_HEIGHT,
              layoutOptions: FIXED_PORTS,
              ports: portsOf(groupId(manifest)),
            }
          : {
              id: groupId(manifest),
              layoutOptions: GROUP_OPTIONS,
              children: members.map((table) => ({
                id: table.id,
                width: NODE_WIDTH,
                height: tableHeight(
                  rows.get(table.id) ?? { columns: [], footer: [], hidden: 0 },
                ),
                layoutOptions: FIXED_PORTS,
                ports: portsOf(table.id),
              })),
            },
      ),
    ],
    edges: edges.map((edge) => ({
      id: edge.id,
      sources: [portId(edge.source, edge.sourceColumn, "out")],
      targets: [portId(edge.target, edge.targetColumn, "in")],
    })),
  };

  let placed: ElkNode;

  try {
    placed = await elk.layout(graph);
  } catch {
    return gridLayout(tables, rows);
  }

  const layoutTables: Record<string, LayoutTable> = {};
  const layoutExternals: Record<string, LayoutRect> = {};
  const groups: LayoutGroup[] = [];

  for (const child of placed.children ?? []) {
    const rect = {
      x: child.x ?? 0,
      y: child.y ?? 0,
      width: child.width ?? NODE_WIDTH,
      height: child.height ?? COMPACT_HEIGHT,
    };

    if (!child.id.startsWith("group:")) {
      layoutExternals[child.id] = rect;
      continue;
    }

    const manifest = child.id.slice("group:".length);
    const members = byManifest.get(manifest) ?? [];

    groups.push({
      ...rect,
      id: child.id,
      manifest,
      members: members.map((table) => table.id),
      collapsed: options.collapsed.has(manifest),
    });

    for (const member of child.children ?? []) {
      const memberRows = rows.get(member.id);

      if (memberRows !== undefined) {
        layoutTables[member.id] = {
          x: member.x ?? 0,
          y: member.y ?? 0,
          width: member.width ?? NODE_WIDTH,
          height: member.height ?? tableHeight(memberRows),
          rows: memberRows,
        };
      }
    }
  }

  const routes = new Map(
    (placed.edges ?? []).map((edge) => [edge.id, pointsOf(edge)]),
  );

  return {
    tables: layoutTables,
    externals: layoutExternals,
    groups,
    edges: edges.map((edge) => ({
      ...edge,
      points: routes.get(edge.id) ?? [],
    })),
  };
}
