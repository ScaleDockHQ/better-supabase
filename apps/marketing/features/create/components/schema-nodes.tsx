"use client";

import type { ReactElement } from "react";

import { Handle, type Node, type NodeProps, Position } from "@xyflow/react";
import {
  ChevronDownIcon,
  ChevronRightIcon,
  ChevronUpIcon,
  KeyRoundIcon,
  Link2Icon,
  LinkIcon,
  PlusIcon,
  UsersIcon,
} from "lucide-react";
import { createContext, use, useMemo } from "react";

import type { SchemaTable } from "@/lib/schema";
import type { TableRows } from "@/lib/schema-layout";

import { Badge } from "@/components/reui/badge";
import { categoryStyle } from "@/features/blocks/categories";
import { BlockIcon } from "@/features/blocks/components/block-icon";
import { installedBlocks, tableFeatures } from "@/lib/record-features";
import { cn } from "@/lib/utils";

import { useDesign } from "./design-provider";

export type InspectorTab =
  | "overview"
  | "columns"
  | "relations"
  | "features"
  | "options"
  | "sql";

/** What a node can ask the canvas to do. */
export interface CanvasActions {
  readonly open: (id: string, tab?: InspectorTab) => void;
  readonly toggleExpand: (id: string) => void;
  readonly toggleGroup: (manifest: string) => void;
  readonly duplicate: (id: string) => void;
  /** Deletes an app table, asking first when other tables reference it or `confirm` is set. */
  readonly requestDelete: (id: string, confirm?: boolean) => void;
  readonly removeBlock: (module: string) => void;
}

const CanvasActionsContext = createContext<CanvasActions | null>(null);

export const CanvasActionsProvider = CanvasActionsContext;

export function useCanvasActions(): CanvasActions {
  const actions = use(CanvasActionsContext);

  if (actions === null) {
    throw new Error("Schema nodes need a CanvasActionsProvider.");
  }

  return actions;
}

export type Emphasis = "none" | "highlight" | "dim";

export interface TableNodeData extends Record<string, unknown> {
  readonly table: SchemaTable;
  readonly rows: TableRows;
  readonly category: string;
  /** "scoped by <tenant>" for tables with a tenant column. */
  readonly scopeLabel: string | null;
  readonly app: boolean;
  readonly soft: ReadonlySet<string>;
  readonly emphasis: Emphasis;
}

export interface CompactNodeData extends Record<string, unknown> {
  readonly label: string;
  readonly emphasis: Emphasis;
}

export interface GroupNodeData extends Record<string, unknown> {
  readonly manifest: string;
  readonly category: string;
  readonly count: number;
  readonly collapsed: boolean;
  readonly emphasis: Emphasis;
}

export type TableNode = Node<TableNodeData, "table">;

export type ExternalNode = Node<CompactNodeData, "external">;

export type GroupNode = Node<GroupNodeData, "blockGroup">;

export type SchemaNode = TableNode | ExternalNode | GroupNode;

const HIDDEN_HANDLE =
  "size-1! min-h-0! min-w-0! border-0! bg-transparent! pointer-events-none";

function emphasisClass(emphasis: Emphasis): string {
  switch (emphasis) {
    case "highlight": {
      return "ring-2 ring-primary/40";
    }

    case "dim": {
      return "opacity-40";
    }

    case "none": {
      return "";
    }

    default: {
      const unreachable: never = emphasis;

      return unreachable;
    }
  }
}

function columnIcon(
  table: SchemaTable,
  soft: ReadonlySet<string>,
  name: string,
): typeof KeyRoundIcon | undefined {
  if (table.primaryKey.includes(name)) {
    return KeyRoundIcon;
  }

  if (table.foreignKeys.some((key) => key.columns.includes(name))) {
    return LinkIcon;
  }

  return soft.has(name) ? Link2Icon : undefined;
}

function displayName(table: SchemaTable): string {
  return table.schema === "better_supabase" || table.schema === "public"
    ? table.name
    : `${table.schema}.${table.name}`;
}

function FooterRowView({
  row,
  hidden,
  id,
}: {
  row: TableRows["footer"][number];
  hidden: number;
  id: string;
}): ReactElement {
  const actions = useCanvasActions();

  switch (row) {
    case "more": {
      return (
        <li className="flex h-6">
          <button
            type="button"
            className="flex flex-1 nodrag items-center gap-2 px-2 text-xs text-muted-foreground tabular-nums transition-colors hover:bg-accent hover:text-foreground"
            onClick={() => {
              actions.toggleExpand(id);
            }}
          >
            <ChevronDownIcon aria-hidden="true" className="size-3.5" />
            <span className="sr-only">Show </span>+{hidden}{" "}
            {hidden === 1 ? "column" : "columns"}
          </button>
        </li>
      );
    }

    case "less": {
      return (
        <li className="flex h-6">
          <button
            type="button"
            className="flex flex-1 nodrag items-center gap-2 px-2 text-xs text-muted-foreground transition-colors hover:bg-accent hover:text-foreground"
            onClick={() => {
              actions.toggleExpand(id);
            }}
          >
            <ChevronUpIcon aria-hidden="true" className="size-3.5" />
            Show fewer
          </button>
        </li>
      );
    }

    case "add": {
      return (
        <li className="flex h-6">
          <button
            type="button"
            className="flex flex-1 nodrag items-center gap-2 px-2 text-xs text-muted-foreground transition-colors hover:bg-accent hover:text-foreground"
            onClick={() => {
              actions.open(id, "columns");
            }}
          >
            <PlusIcon aria-hidden="true" className="size-3.5" />
            Add column
          </button>
        </li>
      );
    }

    default: {
      const unreachable: never = row;

      return unreachable;
    }
  }
}

/** The record features an app table has on, above its node. */
function FeatureBadges({ name }: { name: string }): ReactElement | null {
  const { state } = useDesign();
  const config = state.design.appTables?.[name];

  const installed = useMemo(
    () => installedBlocks(state.preset),
    [state.preset],
  );

  const features = config === undefined ? [] : tableFeatures(config, installed);

  if (features.length === 0) {
    return null;
  }

  return (
    <ul
      aria-label={`${name} features`}
      className="pointer-events-none absolute bottom-full left-0 mb-1 flex max-w-full flex-wrap gap-1"
    >
      {features.map((info) => (
        <li key={info.feature}>
          <Badge variant="primary-light">{info.label}</Badge>
        </li>
      ))}
    </ul>
  );
}

function TableNodeView({ data, selected }: NodeProps<TableNode>): ReactElement {
  const { table, rows, category, scopeLabel, app, soft, emphasis } = data;

  const style = categoryStyle(category);

  return (
    <div
      className={cn(
        "relative flex w-62 flex-col rounded-lg border bg-card text-card-foreground shadow-xs transition-colors",
        app ? "border-dashed border-primary/60" : style.ring,
        selected ? "border-primary" : "",
        emphasisClass(emphasis),
      )}
    >
      {app ? <FeatureBadges name={table.name} /> : null}
      <Handle
        id=":in"
        type="target"
        position={Position.Left}
        isConnectableStart={false}
        isConnectableEnd
        className={cn(HIDDEN_HANDLE, "top-4.5!")}
      />
      <Handle
        id=":out"
        type="source"
        position={Position.Right}
        isConnectable={false}
        className={cn(HIDDEN_HANDLE, "top-4.5!")}
      />
      <div
        className={cn(
          "flex h-9 items-center gap-2 rounded-t-lg border-b px-2",
          app ? "" : cn(style.tint, style.ring),
        )}
      >
        <BlockIcon name={table.module} category={category} size="xs" />
        <span className="min-w-0 flex-1 truncate font-mono text-xs font-medium">
          {displayName(table)}
        </span>
        {scopeLabel === null ? null : (
          <Badge variant="outline" className="max-w-28 truncate">
            {scopeLabel}
          </Badge>
        )}
      </div>
      <ul className="flex flex-col py-1">
        {rows.columns.map((column) => {
          const Icon = columnIcon(table, soft, column.name);

          return (
            <li
              key={column.name}
              className="relative flex h-6 items-center gap-2 px-2"
            >
              <Handle
                id={`${column.name}:in`}
                type="target"
                position={Position.Left}
                isConnectable={false}
                className={HIDDEN_HANDLE}
              />
              <span className="flex size-3.5 shrink-0 items-center justify-center text-muted-foreground">
                {Icon === undefined ? null : (
                  <Icon aria-hidden="true" className="size-3" />
                )}
              </span>
              <span className="min-w-0 flex-1 truncate font-mono text-xs">
                {column.name}
              </span>
              <span
                className="max-w-24 truncate font-mono text-xs text-muted-foreground"
                title={column.label === undefined ? undefined : column.type}
              >
                {column.label ?? column.type}
                {column.nullable ? "?" : ""}
              </span>
              <Handle
                id={`${column.name}:out`}
                type="source"
                position={Position.Right}
                isConnectable={false}
                className={HIDDEN_HANDLE}
              />
            </li>
          );
        })}
        {rows.footer.map((row) => (
          <FooterRowView
            key={row}
            row={row}
            hidden={rows.hidden}
            id={table.id}
          />
        ))}
      </ul>
      <Handle
        id="connect"
        type="source"
        position={Position.Right}
        isConnectableStart
        isConnectableEnd={false}
        aria-label={`Connect ${table.name} to another table`}
        title="Drag onto a table to add a foreign key"
        className="top-4.5! size-3! border-2! border-primary! bg-background!"
      />
    </div>
  );
}

function ExternalNodeView({ data }: NodeProps<ExternalNode>): ReactElement {
  return (
    <div
      className={cn(
        "flex h-10 w-62 items-center gap-2 rounded-lg border border-dashed border-border bg-background px-3 text-muted-foreground transition-colors",
        emphasisClass(data.emphasis),
      )}
    >
      <Handle
        id=":in"
        type="target"
        position={Position.Left}
        isConnectableStart={false}
        isConnectableEnd
        className={HIDDEN_HANDLE}
      />
      <UsersIcon aria-hidden="true" className="size-3.5 shrink-0" />
      <span className="truncate font-mono text-xs">{data.label}</span>
      <span className="ml-auto text-xs">Supabase</span>
      <Handle
        id=":out"
        type="source"
        position={Position.Right}
        isConnectable={false}
        className={HIDDEN_HANDLE}
      />
    </div>
  );
}

function GroupNodeView({ data }: NodeProps<GroupNode>): ReactElement {
  const actions = useCanvasActions();
  const style = categoryStyle(data.category);

  if (data.collapsed) {
    return (
      <div
        className={cn(
          "flex h-10 w-62 items-center rounded-lg border bg-card transition-colors",
          style.ring,
          emphasisClass(data.emphasis),
        )}
      >
        <Handle
          id=":in"
          type="target"
          position={Position.Left}
          isConnectable={false}
          className={HIDDEN_HANDLE}
        />
        <div className="flex h-full flex-1 cursor-grab items-center gap-2 pr-3 text-xs active:cursor-grabbing">
          <button
            type="button"
            className="ml-1 flex size-7 nodrag items-center justify-center rounded-md transition-colors hover:bg-accent"
            onClick={() => {
              actions.toggleGroup(data.manifest);
            }}
          >
            <ChevronRightIcon aria-hidden="true" className="size-3.5" />
            <span className="sr-only">
              Expand {data.manifest}, {data.count}{" "}
              {data.count === 1 ? "table" : "tables"}
            </span>
          </button>
          <BlockIcon name={data.manifest} category={data.category} size="xs" />
          <span aria-hidden="true" className="truncate font-medium">
            {data.manifest}
          </span>
          <span
            aria-hidden="true"
            className="ml-auto text-muted-foreground tabular-nums"
          >
            {data.count}
          </span>
        </div>
        <Handle
          id=":out"
          type="source"
          position={Position.Right}
          isConnectable={false}
          className={HIDDEN_HANDLE}
        />
      </div>
    );
  }

  return (
    <div
      className={cn(
        "size-full rounded-xl border border-dashed transition-colors",
        style.tint,
        style.ring,
        data.emphasis === "dim" ? "opacity-40" : "",
      )}
    >
      <div className="flex h-8 items-center px-1">
        <button
          type="button"
          className="flex h-6 nodrag items-center gap-2 rounded-md px-2 text-xs text-muted-foreground transition-colors hover:text-foreground"
          onClick={() => {
            actions.toggleGroup(data.manifest);
          }}
        >
          <ChevronDownIcon aria-hidden="true" className="size-3.5" />
          <span className="sr-only">Collapse </span>
          <span className="font-medium">{data.manifest}</span>
          <span className="tabular-nums">
            {data.count}
            <span className="sr-only">
              {" "}
              {data.count === 1 ? "table" : "tables"}
            </span>
          </span>
        </button>
      </div>
    </div>
  );
}

/** Not `group`: React Flow gives that type a solid border and a fill. */
export const NODE_TYPES = {
  table: TableNodeView,
  external: ExternalNodeView,
  blockGroup: GroupNodeView,
};
