"use client";

import type { Preset } from "better-supabase/preset";
import type { ReactElement } from "react";

import {
  applyNodeChanges,
  Background,
  BackgroundVariant,
  type FinalConnectionState,
  MiniMap,
  type NodeChange,
  Panel,
  ReactFlow,
  ReactFlowProvider,
  useReactFlow,
} from "@xyflow/react";
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
  APP_MODULE,
  appTableId,
  connect,
  deleteTable,
  duplicateTable,
  isAppTable,
  isEmptyDesign,
  moveTables,
  referenceFrom,
  tidy,
} from "@/lib/design";
import { addPrimitive, type PrimitiveKind } from "@/lib/primitives";
import {
  GROUP_PADDING,
  groupId,
  NODE_WIDTH,
  openingViewport,
  type Point,
  softColumns,
} from "@/lib/schema-layout";
import { cn } from "@/lib/utils";

import { useCanvasBridge } from "./canvas-bridge";
import { DRAG_THRESHOLD, groupFollowers, isControl } from "./canvas-drag";
import { CanvasMenu, type CanvasMenuValue } from "./canvas-menu";
import {
  exportSchema,
  type LayoutInput,
  layoutFor,
  neighboursOf,
  nodeUnder,
  pointerOf,
  toggled,
} from "./canvas-support";
import {
  CanvasToolbar,
  type ExportFormat,
  FIT_VIEW_OPTIONS,
  isKeyboardOwned,
  ZoomControls,
} from "./canvas-toolbar";
import { type ConnectDrop, ConnectDropMenu } from "./connect-drop-menu";
import { DeleteTablesDialog, type PendingDelete } from "./delete-tables-dialog";
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
import { useBlockDrop } from "./use-block-drop";
import { useCollapsedDrag } from "./use-collapsed-drag";
import { usePlacement } from "./use-placement";

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
  const [softRefs, setSoftRefs] = useState(true);
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
  const [drop, setDrop] = useState<ConnectDrop | null>(null);

  const categoryOf = useCallback(
    (table: SchemaTable): string =>
      categories[table.module] ?? "Database primitives",
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

      const category =
        first === undefined ? "Database primitives" : categoryOf(first);

      const base = {
        id: group.id,
        type: "blockGroup" as const,
        draggable: true,
        selectable: false,
        focusable: false,
      };

      if (group.collapsed) {
        const saved = design.positions?.[group.members[0] ?? ""];

        return [
          {
            ...base,
            position:
              saved === undefined
                ? { x: group.x, y: group.y }
                : {
                    x: saved[0] - GROUP_PADDING.side,
                    y: saved[1] - GROUP_PADDING.top,
                  },
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

  const moved = useCallback(
    (id: string): boolean => {
      const members = layout.groups.find((group) => group.id === id)?.members;

      return (members ?? [id]).some(
        (each) => design.positions?.[each] !== undefined,
      );
    },
    [design.positions, layout.groups],
  );

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
            onDelete: edge.onDelete,
            one: edge.one,
            points: edge.points,
            routed: !moved(edge.source) && !moved(edge.target),
            emphasis:
              highlight === undefined ? "none" : touches ? "highlight" : "dim",
          },
        };
      }),
    [highlight, hovered, layout.edges, moved],
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

  const removeAppTables = useCallback(
    (names: readonly string[]) => {
      const ids = new Set(names.map(appTableId));

      actions.apply(
        names.reduce((next, name) => deleteTable(next, name), design),
      );
      setInspector((current) =>
        current !== null && ids.has(current.id) ? null : current,
      );
      setSelected((current) =>
        current !== null && ids.has(current) ? null : current,
      );
      undoToast(
        names.length === 1
          ? `Deleted ${names[0]}.`
          : `Deleted ${String(names.length)} tables.`,
      );
    },
    [actions, design, undoToast],
  );

  const requestDeleteAll = useCallback(
    (ids: readonly string[], confirm = false) => {
      const tables = ids.flatMap((id) => {
        const table = byId.get(id);

        return table !== undefined && isAppTable(table) ? [table] : [];
      });

      if (tables.length === 0) {
        return;
      }

      const chosen = new Set(tables.map((table) => table.id));
      const names = tables.map((table) => table.name);

      const referencedBy = data.tables
        .filter(
          (each) =>
            !chosen.has(each.id) &&
            each.foreignKeys.some((key) =>
              chosen.has(`${key.target.schema}.${key.target.table}`),
            ),
        )
        .map((each) => each.name);

      if (referencedBy.length === 0 && !confirm) {
        removeAppTables(names);
      } else {
        setPendingDelete({ names, referencedBy });
      }
    },
    [byId, data.tables, removeAppTables],
  );

  const requestDelete = useCallback(
    (id: string, confirm = false) => {
      requestDeleteAll([id], confirm);
    },
    [requestDeleteAll],
  );

  const expect = usePlacement(data, input.data, layout.tables);

  /** Adds a primitive at `point`, or in the middle of the view, and opens it. */
  const addAppTable = useCallback(
    (kind: PrimitiveKind = "table", point?: Point, references?: string) => {
      const box = container.current?.getBoundingClientRect();

      const center =
        box === undefined
          ? { x: 0, y: 0 }
          : flow.screenToFlowPosition({
              x: box.left + box.width / 2,
              y: box.top + box.height / 2,
            });

      const at = point ?? {
        x: Math.round(center.x - NODE_WIDTH / 2),
        y: Math.round(center.y - 60),
      };

      const added = addPrimitive(
        design,
        taken,
        kind,
        [Math.round(at.x), Math.round(at.y)],
        preset.idType,
      );

      const linked =
        references === undefined
          ? undefined
          : referenceFrom(added.design, data, preset, added.name, references);

      expect(at, APP_MODULE);
      actions.apply(linked?.ok === true ? linked.design : added.design);
      open(appTableId(added.name), "overview");

      if (linked?.ok === false) {
        toast.error(linked.error);
      }

      undoToast(
        linked?.ok === true
          ? `Added ${added.name} with ${linked.column}.`
          : `Added ${added.name}.`,
      );
    },
    [actions, data, design, expect, flow, open, preset, taken, undoToast],
  );

  const { actions: bridge } = useCanvasBridge();

  useEffect(() => {
    bridge.register({
      addPrimitive: (kind) => {
        addAppTable(kind);
      },
    });
  }, [addAppTable, bridge]);

  useEffect(
    () => () => {
      bridge.register(null);
    },
    [bridge],
  );

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

  const { onNodeDragStart, onNodeDragStop, movesFor } = useCollapsedDrag({
    nodes,
    groups: layout.groups,
    positions: design.positions,
    commitDrag: actions.commitDrag,
  });

  const onNodesChange = useCallback(
    (changes: NodeChange<SchemaNode>[]) => {
      const followers = groupFollowers(
        changes,
        new Map(nodes.map((node) => [node.id, node.position])),
        layout.groups,
      );

      const moves = movesFor(changes);

      for (const change of [...changes, ...followers]) {
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

      setNodes((current) =>
        applyNodeChanges([...changes, ...followers], [...current]),
      );

      if (Object.keys(moves).length > 0) {
        actions.drag(moveTables(design, moves));
      }
    },
    [actions, byId, design, layout.groups, movesFor, nodes],
  );

  const addConnection = useCallback(
    (from: string, to: string) => {
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

  const onConnectEnd = useCallback(
    (event: MouseEvent | TouchEvent, connection: FinalConnectionState) => {
      const from = connection.fromNode?.id;
      const to = connection.toNode?.id ?? nodeUnder(event);
      const pointer = pointerOf(event);

      if (from !== undefined && to === undefined && pointer !== undefined) {
        setDrop({ from, fromName: byId.get(from)?.name ?? from, ...pointer });

        return;
      }

      if (from === undefined || to === undefined || to.startsWith("group:")) {
        return;
      }

      const source = byId.get(from);
      const target = byId.get(to);

      // A block table can't hold the key, so a drag from it onto one of
      // your tables puts the key on yours.
      if (
        source !== undefined &&
        target !== undefined &&
        !isAppTable(source) &&
        isAppTable(target)
      ) {
        addConnection(to, from);
      } else {
        addConnection(from, to);
      }
    },
    [addConnection, byId],
  );

  const blockDrop = useBlockDrop({
    expect,
    undoToast,
    onPrimitive: addAppTable,
  });

  const exportAs = (format: ExportFormat): void => {
    void exportSchema(format, {
      code,
      design,
      data,
      nodes: flow.getNodes(),
      container: container.current,
    });
  };

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
      } else if (key === "enter") {
        const focused =
          event.target instanceof HTMLElement &&
          event.target.matches(".react-flow__node")
            ? event.target.dataset["id"]
            : undefined;

        if (focused !== undefined && byId.has(focused)) {
          open(focused);
        } else if (selected !== null && !isControl(event.target)) {
          open(selected);
        }
      } else if (key === "delete" || key === "backspace") {
        const chosen = flow
          .getNodes()
          .filter((node) => node.type === "table" && node.selected === true)
          .map((node) => node.id);

        if (chosen.length > 0) {
          requestDeleteAll(chosen);
        } else if (selected !== null) {
          requestDelete(selected);
        }
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
    byId,
    flow,
    open,
    requestDelete,
    requestDeleteAll,
    selected,
    state.canRedo,
    state.canUndo,
  ]);

  const tidyUp = useCallback(() => {
    actions.apply(tidy(design));
    void flow.fitView(FIT_VIEW_OPTIONS);
  }, [actions, design, flow]);

  const menu = useMemo(
    (): CanvasMenuValue => ({
      state: {
        data,
        preset,
        layout,
        expanded,
        collapsed,
        softRefs,
        focused: focus ? selected : null,
      },
      actions: {
        addAt: addAppTable,
        connect: addConnection,
        focus: (id) => {
          setSelected(id);
          setFocus((current) => !(current && selected === id));
        },
        find,
        fit: () => {
          void flow.fitView(FIT_VIEW_OPTIONS);
        },
        tidy: tidyUp,
        setSoftRefs,
        setAllCollapsed: (all) => {
          setCollapsed(
            all
              ? new Set(layout.groups.map((group) => group.manifest))
              : new Set(),
          );
        },
        selectTables: (ids) => {
          const chosen = new Set(ids);
          setNodes((current) =>
            current.map((node) =>
              node.type === "table"
                ? { ...node, selected: chosen.has(node.id) }
                : node,
            ),
          );
        },
        undoToast,
      },
    }),
    [
      addAppTable,
      addConnection,
      collapsed,
      data,
      expanded,
      find,
      flow,
      focus,
      layout,
      preset,
      selected,
      softRefs,
      tidyUp,
      undoToast,
    ],
  );

  const categoryNames = useMemo(
    () => [...new Set(data.tables.map(categoryOf))].toSorted(),
    [categoryOf, data.tables],
  );

  return (
    <CanvasActionsProvider value={canvasActions}>
      <CanvasMenu value={menu}>
        <div
          ref={container}
          className={cn("absolute inset-0", FLOW_THEME)}
          onDragOver={blockDrop.onDragOver}
          onDrop={blockDrop.onDrop}
        >
          <SchemaMarkers />
          <ReactFlow<SchemaNode, SchemaEdge>
            nodes={[...nodes]}
            edges={edges}
            nodeTypes={NODE_TYPES}
            edgeTypes={EDGE_TYPES}
            colorMode={resolvedTheme === "dark" ? "dark" : "light"}
            // React Flow's grey attribution falls below 4.5:1 on a group tint,
            // and its unlayered CSS outranks a utility without `!`.
            className="[&_.react-flow\\_\\_attribution_a]:text-muted-foreground!"
            onNodesChange={onNodesChange}
            onNodeDragStart={onNodeDragStart}
            onNodeDragStop={onNodeDragStop}
            nodeDragThreshold={DRAG_THRESHOLD}
            nodeClickDistance={DRAG_THRESHOLD}
            onNodeClick={(event, node) => {
              if (byId.has(node.id) && !isControl(event.target)) {
                open(node.id);
              }
            }}
            onNodeMouseEnter={(_, node) => {
              if (node.type !== "blockGroup") {
                setHovered(node.id);
              }
            }}
            onNodeMouseLeave={() => {
              setHovered(null);
            }}
            // An edge with no click handler ignores the pointer, right-click included.
            onEdgeClick={() => undefined}
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
                onAddTable={() => {
                  addAppTable();
                }}
                onTidy={tidyUp}
                hideSoftRefs={!softRefs}
                onHideSoftRefs={(hide) => {
                  setSoftRefs(!hide);
                }}
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
                onExport={exportAs}
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
              nodeColor={(node) =>
                node.type === "blockGroup" ? "transparent" : ""
              }
            />
          </ReactFlow>
          <ConnectDropMenu
            drop={drop}
            onClose={() => {
              setDrop(null);
            }}
            onPick={(kind, picked) => {
              setDrop(null);
              const at = flow.screenToFlowPosition(picked);
              addAppTable(kind, { x: at.x, y: at.y - 24 }, picked.from);
            }}
          />
        </div>
      </CanvasMenu>
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
      <DeleteTablesDialog
        pending={pendingDelete}
        onCancel={() => {
          setPendingDelete(null);
        }}
        onConfirm={removeAppTables}
      />
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
