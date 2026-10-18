"use client";

import type { Preset } from "better-supabase/preset";
import type { ReactElement } from "react";

import {
  applyNodeChanges,
  Background,
  BackgroundVariant,
  type FinalConnectionState,
  getNodesBounds,
  getViewportForBounds,
  MiniMap,
  type NodeChange,
  Panel,
  ReactFlow,
  ReactFlowProvider,
  useReactFlow,
} from "@xyflow/react";
import { toPng, toSvg } from "html-to-image";
import { useTheme } from "next-themes";
import {
  use,
  useCallback,
  useDeferredValue,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { toast } from "sonner";

import type { SchemaData, SchemaTable } from "@/lib/schema";

import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import {
  addTable,
  appTableId,
  connect,
  deleteTable,
  duplicateTable,
  freeTableName,
  isAppTable,
  isEmptyDesign,
  moveTables,
  tidy,
} from "@/lib/design";
import { toDbml, toJson, toMermaid } from "@/lib/schema-export";
import {
  GROUP_PADDING,
  groupId,
  layoutSchema,
  NODE_WIDTH,
  openingViewport,
  type SchemaLayout,
  softColumns,
} from "@/lib/schema-layout";
import { cn } from "@/lib/utils";

import {
  CanvasToolbar,
  type ExportFormat,
  FIT_VIEW_OPTIONS,
  isKeyboardOwned,
  ZoomControls,
} from "./canvas-toolbar";
import { useDesign } from "./design-provider";
import {
  MARKER_MANY,
  type SchemaEdge,
  SchemaEdgeView,
  SchemaMarkers,
} from "./schema-edge";
import {
  type CanvasActions,
  CanvasActionsProvider,
  type Emphasis,
  type GroupNode,
  type InspectorTab,
  NODE_TYPES,
  type SchemaNode,
  type TableNode,
} from "./schema-nodes";
import { ShortcutsDialog } from "./shortcuts-dialog";
import { TableInspector } from "./table-inspector";

import "@xyflow/react/dist/style.css";

const EDGE_TYPES = { schema: SchemaEdgeView };

const FLOW_THEME = [
  "[--xy-background-color:transparent]",
  "[--xy-background-pattern-color:var(--border)]",
  "[--xy-edge-stroke:color-mix(in_oklab,var(--muted-foreground)_45%,transparent)]",
  "[--xy-connectionline-stroke:var(--primary)]",
  "[--xy-connectionline-stroke-width:1.5]",
  "[--xy-minimap-background-color:var(--card)]",
  "[--xy-minimap-mask-background-color:color-mix(in_oklab,var(--muted)_70%,transparent)]",
  "[--xy-minimap-node-background-color:color-mix(in_oklab,var(--muted-foreground)_35%,transparent)]",
].join(" ");

const SNAP_GRID: [number, number] = [12, 12];

type CanvasPreset = Pick<Preset, "scope" | "tenantName" | "idType">;

interface LayoutInput {
  readonly data: SchemaData;
  readonly expanded: ReadonlySet<string>;
  readonly softRefs: boolean;
  readonly collapsed: ReadonlySet<string>;
  readonly visible: ReadonlySet<string> | undefined;
}

/**
 * One layout per input for the session, so `use` gets the same promise on
 * every render and going back to a view is instant.
 */
const layouts = new Map<string, Promise<SchemaLayout>>();

const LAYOUT_CACHE_LIMIT = 64;

function layoutKey(input: LayoutInput): string {
  return JSON.stringify([
    input.data.tables.map((table) => [
      table.id,
      table.columns.map((column) => column.name),
      table.foreignKeys.map((key) => [
        key.columns,
        key.target.schema,
        key.target.table,
      ]),
    ]),
    input.data.softRefs.map((ref) => [ref.from, ref.column, ref.to]),
    [...input.expanded].toSorted(),
    input.softRefs,
    [...input.collapsed].toSorted(),
    input.visible === undefined ? null : [...input.visible].toSorted(),
  ]);
}

function layoutFor(input: LayoutInput): Promise<SchemaLayout> {
  const key = layoutKey(input);
  const known = layouts.get(key);

  if (known !== undefined) {
    return known;
  }

  if (layouts.size >= LAYOUT_CACHE_LIMIT) {
    layouts.clear();
  }

  const layout = layoutSchema(input.data, {
    expanded: input.expanded,
    softRefs: input.softRefs,
    collapsed: input.collapsed,
    visible: input.visible,
    isApp: isAppTable,
  });

  layouts.set(key, layout);

  return layout;
}

function toggled<T>(
  set: ReadonlySet<T>,
  value: T,
  on?: boolean,
): ReadonlySet<T> {
  const next = new Set(set);

  if (on ?? !next.has(value)) {
    next.add(value);
  } else {
    next.delete(value);
  }

  return next;
}

/** The tables each table references or is referenced by, soft references included. */
function neighboursOf(
  data: SchemaData,
): ReadonlyMap<string, ReadonlySet<string>> {
  const map = new Map<string, Set<string>>();

  const link = (a: string, b: string): void => {
    map.set(a, (map.get(a) ?? new Set()).add(b));
    map.set(b, (map.get(b) ?? new Set()).add(a));
  };

  for (const table of data.tables) {
    for (const key of table.foreignKeys) {
      link(table.id, `${key.target.schema}.${key.target.table}`);
    }
  }

  for (const ref of data.softRefs) {
    if (ref.to !== null) {
      link(ref.from, ref.to);
    }
  }

  return map;
}

function download(name: string, href: string): void {
  const anchor = document.createElement("a");
  anchor.href = href;
  anchor.download = name;
  anchor.click();
}

function downloadText(name: string, text: string, type: string): void {
  const url = URL.createObjectURL(new Blob([text], { type }));
  download(name, url);
  URL.revokeObjectURL(url);
}

function pointerOf(
  event: MouseEvent | TouchEvent,
): { x: number; y: number } | undefined {
  if ("changedTouches" in event) {
    const touch = event.changedTouches[0];

    return touch === undefined
      ? undefined
      : { x: touch.clientX, y: touch.clientY };
  }

  return { x: event.clientX, y: event.clientY };
}

/** The node under the pointer, so dropping a connection anywhere on a table works. */
function nodeUnder(event: MouseEvent | TouchEvent): string | undefined {
  const point = pointerOf(event);

  const element =
    point === undefined ? null : document.elementFromPoint(point.x, point.y);

  const node = element?.closest<HTMLElement>(".react-flow__node");

  return node?.dataset["id"];
}

interface PendingDelete {
  readonly name: string;
  readonly referencedBy: readonly string[];
}

interface CanvasProps {
  readonly code: string;
  readonly designCode: string;
  readonly data: SchemaData;
  readonly preset: CanvasPreset;
  readonly categories: Readonly<Record<string, string>>;
  readonly onRemoveBlock: (module: string) => void;
}

function CanvasInner({
  code,
  designCode,
  data,
  preset,
  categories,
  onRemoveBlock,
}: CanvasProps): ReactElement {
  const { resolvedTheme } = useTheme();
  const { state, actions } = useDesign();
  const { design } = state;
  const flow = useReactFlow<SchemaNode, SchemaEdge>();
  const container = useRef<HTMLDivElement>(null);

  const [expanded, setExpanded] = useState<ReadonlySet<string>>(new Set());
  const [collapsed, setCollapsed] = useState<ReadonlySet<string>>(new Set());
  const [softRefs, setSoftRefs] = useState(false);
  const [snap, setSnap] = useState(false);
  const [focus, setFocus] = useState(false);

  const [hiddenCategories, setHiddenCategories] = useState<ReadonlySet<string>>(
    new Set(),
  );

  const [hovered, setHovered] = useState<string | null>(null);
  const [selected, setSelected] = useState<string | null>(null);

  const [inspector, setInspector] = useState<{
    id: string;
    tab: InspectorTab;
  } | null>(null);

  const [pendingDelete, setPendingDelete] = useState<PendingDelete | null>(
    null,
  );

  const [shortcutsOpen, setShortcutsOpen] = useState(false);

  const categoryOf = useCallback(
    (table: SchemaTable): string => categories[table.module] ?? "Platform",
    [categories],
  );

  const neighbours = useMemo(() => neighboursOf(data), [data]);
  const soft = useMemo(() => softColumns(data), [data]);

  const byId = useMemo(
    () => new Map(data.tables.map((table) => [table.id, table])),
    [data],
  );

  const selectedTable = selected === null ? undefined : byId.get(selected);

  const visible = useMemo((): ReadonlySet<string> | undefined => {
    const focused =
      focus && selectedTable !== undefined
        ? new Set([
            selectedTable.id,
            ...(neighbours.get(selectedTable.id) ?? []),
          ])
        : undefined;

    if (focused === undefined && hiddenCategories.size === 0) {
      return undefined;
    }

    return new Set(
      data.tables
        .filter(
          (table) =>
            (focused === undefined || focused.has(table.id)) &&
            !hiddenCategories.has(categoryOf(table)),
        )
        .map((table) => table.id),
    );
  }, [categoryOf, data, focus, hiddenCategories, neighbours, selectedTable]);

  const input = useDeferredValue<LayoutInput>(
    useMemo(
      () => ({ data, expanded, softRefs, collapsed, visible }),
      [collapsed, data, expanded, softRefs, visible],
    ),
  );

  const layout = use(layoutFor(input));

  const highlight = useMemo((): ReadonlySet<string> | undefined => {
    const anchor = hovered ?? null;

    return anchor === null
      ? undefined
      : new Set([anchor, ...(neighbours.get(anchor) ?? [])]);
  }, [hovered, neighbours]);

  const emphasisOf = useCallback(
    (id: string): Emphasis =>
      highlight === undefined
        ? "none"
        : highlight.has(id)
          ? "highlight"
          : "dim",
    [highlight],
  );

  const scopeLabel =
    preset.scope === "tenant" ? `scoped by ${preset.tenantName}` : null;

  const derived = useMemo((): readonly SchemaNode[] => {
    const tableNodes = Object.entries(layout.tables).flatMap(
      ([id, rect]): TableNode[] => {
        const table = byId.get(id);

        if (table === undefined) {
          return [];
        }

        const saved = design.positions?.[id];

        return [
          {
            id,
            type: "table",
            position:
              saved === undefined
                ? { x: rect.x, y: rect.y }
                : { x: saved[0], y: saved[1] },
            width: rect.width,
            height: rect.height,
            data: {
              table,
              rows: rect.rows,
              category: categoryOf(table),
              scopeLabel: table.tenantColumn === null ? null : scopeLabel,
              app: isAppTable(table),
              soft: soft.get(id) ?? new Set(),
              emphasis: emphasisOf(id),
            },
          },
        ];
      },
    );

    const placed = new Map(tableNodes.map((node) => [node.id, node]));

    const groupNodes = layout.groups.flatMap((group): GroupNode[] => {
      const first = byId.get(group.members[0] ?? "");
      const category = first === undefined ? "Platform" : categoryOf(first);

      const base = {
        id: group.id,
        type: "group" as const,
        draggable: false,
        selectable: false,
        focusable: false,
      };

      if (group.collapsed) {
        return [
          {
            ...base,
            position: { x: group.x, y: group.y },
            data: {
              manifest: group.manifest,
              category,
              count: group.members.length,
              collapsed: true,
              emphasis: "none",
            },
          },
        ];
      }

      const members = group.members.flatMap((id) => {
        const node = placed.get(id);

        return node === undefined ? [] : [node];
      });

      if (members.length === 0) {
        return [];
      }

      const minX = Math.min(...members.map((node) => node.position.x));
      const minY = Math.min(...members.map((node) => node.position.y));

      const maxX = Math.max(
        ...members.map((node) => node.position.x + (node.width ?? NODE_WIDTH)),
      );

      const maxY = Math.max(
        ...members.map((node) => node.position.y + (node.height ?? 0)),
      );

      return [
        {
          ...base,
          position: {
            x: minX - GROUP_PADDING.side,
            y: minY - GROUP_PADDING.top,
          },
          width: maxX - minX + GROUP_PADDING.side * 2,
          height: maxY - minY + GROUP_PADDING.top + GROUP_PADDING.bottom,
          zIndex: -1,
          style: { pointerEvents: "none" },
          data: {
            manifest: group.manifest,
            category,
            count: members.length,
            collapsed: false,
            emphasis:
              highlight === undefined ||
              members.some((node) => highlight.has(node.id))
                ? "none"
                : "dim",
          },
        },
      ];
    });

    const externalNodes = Object.entries(layout.externals).map(
      ([id, rect]): SchemaNode => ({
        id,
        type: "external",
        position: { x: rect.x, y: rect.y },
        draggable: false,
        data: { label: id, emphasis: emphasisOf(id) },
      }),
    );

    return [...groupNodes, ...externalNodes, ...tableNodes];
  }, [
    byId,
    categoryOf,
    design.positions,
    emphasisOf,
    highlight,
    layout,
    scopeLabel,
    soft,
  ]);

  const [nodes, setNodes] = useState<readonly SchemaNode[]>(derived);
  const [source, setSource] = useState(derived);

  if (source !== derived) {
    const previous = new Map(nodes.map((node) => [node.id, node]));
    setSource(derived);
    setNodes(
      derived.map((node) => {
        const before = previous.get(node.id);

        if (before === undefined) {
          return node;
        }

        const merged: SchemaNode = { ...node };

        if (before.selected !== undefined) {
          merged.selected = before.selected;
        }

        if (before.dragging !== undefined) {
          merged.dragging = before.dragging;
        }

        if (before.measured !== undefined) {
          merged.measured = before.measured;
        }

        return merged;
      }),
    );
  }

  const edges = useMemo(
    (): SchemaEdge[] =>
      layout.edges.map((edge) => {
        const touches =
          highlight !== undefined &&
          (edge.source === hovered || edge.target === hovered);

        return {
          id: edge.id,
          type: "schema",
          source: edge.source,
          sourceHandle: `${edge.sourceColumn ?? ""}:out`,
          target: edge.target,
          targetHandle: `${edge.targetColumn ?? ""}:in`,
          focusable: false,
          selectable: false,
          data: {
            kind: edge.kind,
            points: edge.points,
            routed:
              design.positions?.[edge.source] === undefined &&
              design.positions?.[edge.target] === undefined,
            emphasis:
              highlight === undefined ? "none" : touches ? "highlight" : "dim",
          },
        };
      }),
    [design.positions, highlight, hovered, layout.edges],
  );

  const taken = useMemo(
    () => new Set(data.tables.map((table) => table.id)),
    [data.tables],
  );

  const undoToast = useCallback(
    (message: string) => {
      toast.success(message, {
        action: { label: "Undo", onClick: actions.undo },
      });
    },
    [actions.undo],
  );

  const open = useCallback((id: string, tab: InspectorTab = "overview") => {
    setSelected(id);
    setInspector({ id, tab });
  }, []);

  const removeAppTable = useCallback(
    (name: string) => {
      actions.apply(deleteTable(design, name));
      setInspector((current) =>
        current?.id === appTableId(name) ? null : current,
      );
      setSelected((current) => (current === appTableId(name) ? null : current));
      undoToast(`Deleted ${name}.`);
    },
    [actions, design, undoToast],
  );

  const requestDelete = useCallback(
    (id: string) => {
      const table = byId.get(id);

      if (table === undefined || !isAppTable(table)) {
        return;
      }

      const referencedBy = data.tables
        .filter(
          (each) =>
            each.id !== id &&
            each.foreignKeys.some(
              (key) => `${key.target.schema}.${key.target.table}` === id,
            ),
        )
        .map((each) => each.name);

      if (referencedBy.length === 0) {
        removeAppTable(table.name);
      } else {
        setPendingDelete({ name: table.name, referencedBy });
      }
    },
    [byId, data.tables, removeAppTable],
  );

  const addAppTable = useCallback(() => {
    const name = freeTableName(design, taken);
    const box = container.current?.getBoundingClientRect();

    const center =
      box === undefined
        ? { x: 0, y: 0 }
        : flow.screenToFlowPosition({
            x: box.left + box.width / 2,
            y: box.top + box.height / 2,
          });

    actions.apply(
      addTable(design, name, {}, [
        Math.round(center.x - NODE_WIDTH / 2),
        Math.round(center.y - 60),
      ]),
    );
    open(appTableId(name), "overview");
    undoToast(`Added ${name}.`);
  }, [actions, design, flow, open, taken, undoToast]);

  const canvasActions = useMemo(
    (): CanvasActions => ({
      open,
      toggleExpand: (id) => {
        setExpanded((current) => toggled(current, id));
      },
      toggleGroup: (manifest) => {
        setCollapsed((current) => toggled(current, manifest));
      },
      duplicate: (id) => {
        const table = byId.get(id);

        if (table === undefined || !isAppTable(table)) {
          return;
        }

        const result = duplicateTable(design, table.name, taken);
        actions.apply(result.design);
        undoToast(`Duplicated ${table.name} as ${result.name}.`);
      },
      requestDelete,
      removeBlock: onRemoveBlock,
    }),
    [
      actions,
      byId,
      design,
      onRemoveBlock,
      open,
      requestDelete,
      taken,
      undoToast,
    ],
  );

  const onNodesChange = useCallback(
    (changes: NodeChange<SchemaNode>[]) => {
      setNodes((current) => applyNodeChanges(changes, [...current]));

      const moves: Record<string, readonly [number, number]> = {};

      for (const change of changes) {
        if (
          change.type === "position" &&
          change.position !== undefined &&
          byId.has(change.id)
        ) {
          moves[change.id] = [
            Math.round(change.position.x),
            Math.round(change.position.y),
          ];
        }

        if (
          change.type === "select" &&
          byId.has(change.id) &&
          change.selected
        ) {
          setSelected(change.id);
        }
      }

      if (Object.keys(moves).length > 0) {
        actions.drag(moveTables(design, moves));
      }
    },
    [actions, byId, design],
  );

  const onConnectEnd = useCallback(
    (event: MouseEvent | TouchEvent, connection: FinalConnectionState) => {
      const from = connection.fromNode?.id;
      const to = connection.toNode?.id ?? nodeUnder(event);

      if (from === undefined || to === undefined || to.startsWith("group:")) {
        return;
      }

      const result = connect(design, data, preset, {
        source: from,
        target: to,
      });

      if (result.ok) {
        actions.apply(result.design);
        undoToast(`Added ${result.column} to ${byId.get(from)?.name ?? from}.`);
      } else {
        toast.error(result.error);
      }
    },
    [actions, byId, data, design, preset, undoToast],
  );

  const exportAs = useCallback(
    async (format: ExportFormat) => {
      switch (format) {
        case "mermaid": {
          downloadText("schema.mmd", toMermaid(data), "text/plain");
          break;
        }

        case "dbml": {
          downloadText("schema.dbml", toDbml(data), "text/plain");
          break;
        }

        case "json": {
          downloadText(
            "schema.json",
            toJson(code, design, data),
            "application/json",
          );
          break;
        }

        case "png":
        case "svg": {
          const viewport = container.current?.querySelector<HTMLElement>(
            ".react-flow__viewport",
          );

          if (viewport === undefined || viewport === null) {
            return;
          }

          const bounds = getNodesBounds(flow.getNodes());
          const width = Math.min(Math.max(bounds.width + 64, 640), 4096);
          const height = Math.min(Math.max(bounds.height + 64, 480), 4096);

          const transform = getViewportForBounds(
            bounds,
            width,
            height,
            0.1,
            2,
            0.05,
          );

          const options = {
            width,
            height,
            backgroundColor: getComputedStyle(document.body).backgroundColor,
            style: {
              width: `${width}px`,
              height: `${height}px`,
              transform: `translate(${transform.x}px, ${transform.y}px) scale(${transform.zoom})`,
            },
          };

          try {
            const url =
              format === "png"
                ? await toPng(viewport, options)
                : await toSvg(viewport, options);

            download(`schema.${format}`, url);
          } catch {
            toast.error(
              "The image could not be drawn. Try the SVG or Mermaid export.",
            );

            return;
          }

          break;
        }

        default: {
          const unreachable: never = format;

          return unreachable;
        }
      }

      toast.success(
        `Downloaded schema.${format === "mermaid" ? "mmd" : format}.`,
      );
    },
    [code, data, design, flow],
  );

  const find = useCallback(
    (id: string) => {
      setSelected(id);
      void flow.fitView({ nodes: [{ id }], maxZoom: 1, duration: 200 });
    },
    [flow],
  );

  useEffect(() => {
    function onKeyDown(event: KeyboardEvent): void {
      if (
        event.defaultPrevented ||
        event.isComposing ||
        event.altKey ||
        isKeyboardOwned(event.target)
      ) {
        return;
      }

      const key = event.key.toLowerCase();

      if (event.metaKey || event.ctrlKey) {
        // Claims the key only when it acts, so the page keeps its own undo.
        if (key === "z" && event.shiftKey && state.canRedo) {
          event.preventDefault();
          actions.redo();
        } else if (key === "z" && !event.shiftKey && state.canUndo) {
          event.preventDefault();
          actions.undo();
        }

        return;
      }

      if (event.shiftKey && event.code === "Digit1") {
        void flow.fitView(FIT_VIEW_OPTIONS);
      } else if (event.key === "?") {
        setShortcutsOpen(true);
      } else if (key === "n") {
        addAppTable();
      } else if (key === "f" && selected !== null) {
        setFocus((current) => !current);
      } else if (key === "+" || key === "=") {
        void flow.zoomIn();
      } else if (key === "-") {
        void flow.zoomOut();
      } else if (key === "enter" && selected !== null) {
        open(selected);
      } else if (
        (key === "delete" || key === "backspace") &&
        selected !== null
      ) {
        requestDelete(selected);
      } else if (key === "escape") {
        setFocus(false);
        setSelected(null);
      }
    }

    window.addEventListener("keydown", onKeyDown);

    return () => {
      window.removeEventListener("keydown", onKeyDown);
    };
  }, [
    actions,
    addAppTable,
    flow,
    open,
    requestDelete,
    selected,
    state.canRedo,
    state.canUndo,
  ]);

  const categoryNames = useMemo(
    () => [...new Set(data.tables.map(categoryOf))].toSorted(),
    [categoryOf, data.tables],
  );

  return (
    <CanvasActionsProvider value={canvasActions}>
      <div ref={container} className={cn("absolute inset-0", FLOW_THEME)}>
        <SchemaMarkers />
        <ReactFlow<SchemaNode, SchemaEdge>
          nodes={[...nodes]}
          edges={edges}
          nodeTypes={NODE_TYPES}
          edgeTypes={EDGE_TYPES}
          colorMode={resolvedTheme === "dark" ? "dark" : "light"}
          onNodesChange={onNodesChange}
          onNodeDragStop={actions.commitDrag}
          onNodeClick={(_, node) => {
            if (byId.has(node.id)) {
              setSelected(node.id);
            }
          }}
          onNodeDoubleClick={(_, node) => {
            if (byId.has(node.id)) {
              open(node.id);
            }
          }}
          onNodeMouseEnter={(_, node) => {
            if (node.type !== "group") {
              setHovered(node.id);
            }
          }}
          onNodeMouseLeave={() => {
            setHovered(null);
          }}
          onPaneClick={() => {
            setSelected(null);
          }}
          onConnectEnd={onConnectEnd}
          connectionRadius={32}
          connectionLineStyle={{ markerEnd: `url(#${MARKER_MANY})` }}
          deleteKeyCode={null}
          nodesConnectable
          elementsSelectable
          snapToGrid={snap}
          snapGrid={SNAP_GRID}
          zoomOnDoubleClick={false}
          onInit={(instance) => {
            const element = container.current;

            if (element === null) {
              return;
            }

            const rects = new Map(
              instance.getNodes().map((node) => [
                node.id,
                {
                  ...node.position,
                  width: node.width ?? 0,
                  height: node.height ?? 0,
                },
              ]),
            );

            const tenant = data.tenantTable;

            const anchor =
              tenant === null
                ? undefined
                : (rects.get(groupId(data.manifests[tenant] ?? tenant)) ??
                  rects.get(tenant));

            void instance.setViewport(
              openingViewport(
                [...rects.values()],
                element.clientWidth,
                element.clientHeight,
                anchor,
              ),
            );
          }}
          minZoom={0.1}
          maxZoom={2}
        >
          <Background variant={BackgroundVariant.Dots} gap={24} size={2} />
          <Panel position="top-left" className="max-w-[calc(100%-2rem)]">
            <CanvasToolbar
              canUndo={state.canUndo}
              canRedo={state.canRedo}
              onUndo={actions.undo}
              onRedo={actions.redo}
              onAddTable={addAppTable}
              onTidy={() => {
                actions.apply(tidy(design));
                void flow.fitView(FIT_VIEW_OPTIONS);
              }}
              softRefs={softRefs}
              onSoftRefs={setSoftRefs}
              snap={snap}
              onSnap={setSnap}
              focus={focus}
              canFocus={selected !== null}
              onFocus={setFocus}
              tables={data.tables.map((table) => ({
                id: table.id,
                label: table.name,
              }))}
              onFind={find}
              categories={categoryNames}
              hiddenCategories={hiddenCategories}
              onCategory={(category, shown) => {
                setHiddenCategories((current) =>
                  toggled(current, category, !shown),
                );
              }}
              onExport={(format) => {
                void exportAs(format);
              }}
              onShortcuts={() => {
                setShortcutsOpen(true);
              }}
              canReset={!isEmptyDesign(design)}
              onReset={() => {
                actions.apply({});
                undoToast("Reset the schema to the preset.");
              }}
            />
          </Panel>
          <Panel position="bottom-right">
            <ZoomControls />
          </Panel>
          <MiniMap
            position="bottom-left"
            pannable
            zoomable
            ariaLabel="Schema overview"
            className="hidden sm:block"
            nodeColor={(node) => (node.type === "group" ? "transparent" : "")}
          />
        </ReactFlow>
      </div>
      <TableInspector
        table={inspector === null ? undefined : byId.get(inspector.id)}
        tab={inspector?.tab ?? "overview"}
        onTab={(tab) => {
          setInspector((current) =>
            current === null ? null : { ...current, tab },
          );
        }}
        onClose={() => {
          setInspector(null);
        }}
        onOpen={open}
        onDelete={requestDelete}
        code={code}
        designCode={designCode}
        data={data}
        preset={preset}
      />
      <AlertDialog
        open={pendingDelete !== null}
        onOpenChange={(next) => {
          if (!next) {
            setPendingDelete(null);
          }
        }}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete {pendingDelete?.name}?</AlertDialogTitle>
            <AlertDialogDescription>
              {pendingDelete?.referencedBy.join(", ")}{" "}
              {pendingDelete?.referencedBy.length === 1
                ? "references"
                : "reference"}{" "}
              this table. Deleting it also removes those columns.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              variant="destructive"
              onClick={() => {
                if (pendingDelete !== null) {
                  removeAppTable(pendingDelete.name);
                }

                setPendingDelete(null);
              }}
            >
              Delete
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
      <ShortcutsDialog open={shortcutsOpen} onOpenChange={setShortcutsOpen} />
    </CanvasActionsProvider>
  );
}

/**
 * The tables as an entity diagram you can edit: app tables, connections,
 * extra columns and positions go into the design, everything else stays
 * view state. The table list next to it carries the same content for screen
 * readers.
 */
export function SchemaCanvas(props: CanvasProps): ReactElement {
  return (
    <ReactFlowProvider>
      <CanvasInner {...props} />
    </ReactFlowProvider>
  );
}
