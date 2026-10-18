"use client";

import type { ElkNode } from "elkjs/lib/elk-api";
import type { ReactElement } from "react";

import {
  Background,
  type Edge,
  Handle,
  MarkerType,
  type Node,
  type NodeProps,
  Panel,
  Position,
  ReactFlow,
  useReactFlow,
} from "@xyflow/react";
import ELK from "elkjs/lib/elk.bundled.js";
import {
  ExpandIcon,
  KeyRoundIcon,
  LinkIcon,
  UsersIcon,
  ZoomInIcon,
  ZoomOutIcon,
} from "lucide-react";
import { useTheme } from "next-themes";
import { use } from "react";

import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import { categoryStyle } from "@/features/blocks/categories";
import { BlockIcon } from "@/features/blocks/components/block-icon";
import { type SchemaTable, schemaRelations } from "@/lib/schema";
import { cn } from "@/lib/utils";

import "@xyflow/react/dist/style.css";

// The layout sizes match the node classes: w-62, h-9 header, h-6 rows, h-10 external.
const NODE_WIDTH = 248;
const HEADER_HEIGHT = 36;
const ROW_HEIGHT = 24;
const PADDING = 8;
const EXTERNAL_HEIGHT = 40;

interface TableData extends Record<string, unknown> {
  readonly table: SchemaTable;
  readonly category: string;
}

interface ExternalData extends Record<string, unknown> {
  readonly id: string;
}

type TableNode = Node<TableData, "table">;

type ExternalNode = Node<ExternalData, "external">;

type DiagramNode = TableNode | ExternalNode;

interface Diagram {
  readonly nodes: readonly DiagramNode[];
  readonly edges: readonly Edge[];
}

function tableHeight(table: SchemaTable): number {
  const more = table.columnCount > table.keyColumns.length ? 1 : 0;

  return (
    HEADER_HEIGHT + (table.keyColumns.length + more) * ROW_HEIGHT + PADDING
  );
}

const elk = new ELK();

async function layoutDiagram(
  tables: readonly SchemaTable[],
  categories: Readonly<Record<string, string>>,
): Promise<Diagram> {
  const known = new Set(tables.map((table) => table.id));
  const relations = schemaRelations(tables);

  const external = [
    ...new Set(
      relations.flatMap((relation) =>
        known.has(relation.to) ? [] : [relation.to],
      ),
    ),
  ];

  const graph: ElkNode = {
    id: "root",
    layoutOptions: {
      "elk.algorithm": "layered",
      "elk.direction": "RIGHT",
      "elk.layered.spacing.nodeNodeBetweenLayers": "72",
      "elk.spacing.nodeNode": "32",
      "elk.layered.nodePlacement.strategy": "BRANDES_KOEPF",
    },
    children: [
      ...external.map((id) => ({
        id,
        width: NODE_WIDTH,
        height: EXTERNAL_HEIGHT,
      })),
      ...tables.map((table) => ({
        id: table.id,
        width: NODE_WIDTH,
        height: tableHeight(table),
      })),
    ],
    // Referenced tables lead, so the layered layout reads parent to child.
    edges: relations.map((relation) => ({
      id: `${relation.from}->${relation.to}`,
      sources: [relation.to],
      targets: [relation.from],
    })),
  };

  // A failed layout still draws every table, in a plain grid.
  const placed = await elk.layout(graph).catch((): ElkNode => ({
    ...graph,
    children: (graph.children ?? []).map((child, index) => ({
      ...child,
      x: (index % 4) * (NODE_WIDTH + 48),
      y: Math.floor(index / 4) * 240,
    })),
  }));

  const positions = new Map(
    (placed.children ?? []).map((child) => [
      child.id,
      { x: child.x ?? 0, y: child.y ?? 0 },
    ]),
  );

  const nodes: DiagramNode[] = [
    ...external.map((id): ExternalNode => ({
      id,
      type: "external",
      position: positions.get(id) ?? { x: 0, y: 0 },
      data: { id },
    })),
    ...tables.map((table): TableNode => ({
      id: table.id,
      type: "table",
      position: positions.get(table.id) ?? { x: 0, y: 0 },
      data: {
        table,
        category: categories[table.module] ?? "Database primitives",
      },
    })),
  ];

  const edges = relations.map((relation): Edge => ({
    id: `${relation.from}->${relation.to}`,
    source: relation.to,
    target: relation.from,
    type: "smoothstep",
    markerStart: { type: MarkerType.ArrowClosed, width: 16, height: 16 },
  }));

  return { nodes, edges };
}

/**
 * One layout per preset code for the session, so `use` gets the same
 * promise on every render and going back to a selection is instant.
 */
const layouts = new Map<string, Promise<Diagram>>();

function diagramFor(
  code: string,
  tables: readonly SchemaTable[],
  categories: Readonly<Record<string, string>>,
): Promise<Diagram> {
  const known = layouts.get(code);

  if (known !== undefined) {
    return known;
  }

  const layout = layoutDiagram(tables, categories);
  layouts.set(code, layout);

  return layout;
}

function columnIcon(
  table: SchemaTable,
  name: string,
): typeof KeyRoundIcon | undefined {
  if (table.primaryKey.includes(name)) {
    return KeyRoundIcon;
  }

  if (table.foreignKeys.some((key) => key.columns.includes(name))) {
    return LinkIcon;
  }

  return undefined;
}

const HIDDEN_HANDLE = "size-1! min-h-0! min-w-0! border-0! bg-transparent!";

function TableNodeView({ data }: NodeProps<TableNode>): ReactElement {
  const { table, category } = data;
  const style = categoryStyle(category);
  const more = table.columnCount - table.keyColumns.length;

  return (
    <div
      className={cn(
        "flex w-62 flex-col overflow-hidden rounded-lg border bg-card text-card-foreground shadow-xs",
        style.ring,
      )}
    >
      <Handle
        type="target"
        position={Position.Left}
        isConnectable={false}
        className={HIDDEN_HANDLE}
      />
      <div
        className={cn(
          "flex h-9 items-center gap-2 border-b px-2",
          style.tint,
          style.ring,
        )}
      >
        <BlockIcon name={table.module} category={category} size="xs" />
        <span className="min-w-0 flex-1 truncate font-mono text-xs font-medium">
          {table.schema === "better_supabase"
            ? table.name
            : `${table.schema}.${table.name}`}
        </span>
        <Badge variant="outline" className="max-w-24 truncate">
          {table.module}
        </Badge>
      </div>
      <ul className="flex flex-col py-1">
        {table.keyColumns.map((column) => {
          const Icon = columnIcon(table, column.name);

          return (
            <li key={column.name} className="flex h-6 items-center gap-2 px-2">
              <span className="flex size-3.5 shrink-0 items-center justify-center text-muted-foreground">
                {Icon === undefined ? null : (
                  <Icon aria-hidden="true" className="size-3" />
                )}
              </span>
              <span className="min-w-0 flex-1 truncate font-mono text-xs">
                {column.name}
              </span>
              <span className="truncate font-mono text-xs text-muted-foreground">
                {column.type}
              </span>
            </li>
          );
        })}
        {more > 0 ? (
          <li className="flex h-6 items-center px-2 pl-7.5 text-xs text-muted-foreground tabular-nums">
            +{more} {more === 1 ? "column" : "columns"}
          </li>
        ) : null}
      </ul>
      <Handle
        type="source"
        position={Position.Right}
        isConnectable={false}
        className={HIDDEN_HANDLE}
      />
    </div>
  );
}

function ExternalNodeView({ data }: NodeProps<ExternalNode>): ReactElement {
  return (
    <div className="flex h-10 w-62 items-center gap-2 rounded-lg border border-dashed border-border bg-muted px-3 text-muted-foreground">
      <UsersIcon aria-hidden="true" className="size-3.5 shrink-0" />
      <span className="truncate font-mono text-xs">{data.id}</span>
      <span className="ml-auto text-xs">Supabase</span>
      <Handle
        type="source"
        position={Position.Right}
        isConnectable={false}
        className={HIDDEN_HANDLE}
      />
    </div>
  );
}

const NODE_TYPES = { table: TableNodeView, external: ExternalNodeView };

function ViewControls(): ReactElement {
  const { fitView, zoomIn, zoomOut } = useReactFlow();

  return (
    <Panel position="top-right" className="flex gap-1">
      <Button
        type="button"
        variant="outline"
        size="icon-sm"
        aria-label="Zoom in"
        onClick={() => {
          void zoomIn();
        }}
      >
        <ZoomInIcon aria-hidden="true" />
      </Button>
      <Button
        type="button"
        variant="outline"
        size="icon-sm"
        aria-label="Zoom out"
        onClick={() => {
          void zoomOut();
        }}
      >
        <ZoomOutIcon aria-hidden="true" />
      </Button>
      <Button
        type="button"
        variant="outline"
        size="icon-sm"
        aria-label="Fit the schema in view"
        onClick={() => {
          void fitView({ padding: 0.1 });
        }}
      >
        <ExpandIcon aria-hidden="true" />
      </Button>
    </Panel>
  );
}

/**
 * The tables as an entity diagram you can pan and zoom but not edit. The
 * table list next to it carries the same content for screen readers.
 */
export function SchemaCanvas({
  code,
  tables,
  categories,
}: {
  code: string;
  tables: readonly SchemaTable[];
  categories: Readonly<Record<string, string>>;
}): ReactElement {
  const { resolvedTheme } = useTheme();
  const diagram = use(diagramFor(code, tables, categories));

  return (
    <div className="absolute inset-0">
      <ReactFlow
        nodes={[...diagram.nodes]}
        edges={[...diagram.edges]}
        nodeTypes={NODE_TYPES}
        colorMode={resolvedTheme === "dark" ? "dark" : "light"}
        nodesDraggable={false}
        nodesConnectable={false}
        elementsSelectable={false}
        nodesFocusable={false}
        edgesFocusable={false}
        fitView
        fitViewOptions={{ padding: 0.1 }}
        minZoom={0.1}
      >
        <Background gap={24} />
        <ViewControls />
      </ReactFlow>
    </div>
  );
}
