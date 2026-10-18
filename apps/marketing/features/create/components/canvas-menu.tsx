"use client";

import type { KeyboardEvent, MouseEvent, ReactElement, ReactNode } from "react";

import { useReactFlow } from "@xyflow/react";
import { resolvePreset } from "better-supabase/preset";
import {
  ArrowRightIcon,
  ClipboardCopyIcon,
  CopyIcon,
  FocusIcon,
  FoldVerticalIcon,
  LayoutGridIcon,
  ListIcon,
  MaximizeIcon,
  MousePointerClickIcon,
  PanelLeftIcon,
  PanelRightOpenIcon,
  PencilIcon,
  PlusIcon,
  SplineIcon,
  TableIcon,
  Trash2Icon,
  UnfoldVerticalIcon,
} from "lucide-react";
import { createContext, use, useState } from "react";
import { toast } from "sonner";

import type { Design } from "@/lib/design";
import type { PrimitiveKind } from "@/lib/primitives";
import type { SchemaData, SchemaTable } from "@/lib/schema";
import type {
  LayoutEdge,
  LayoutGroup,
  Point,
  SchemaLayout,
} from "@/lib/schema-layout";

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
  ContextMenu,
  ContextMenuCheckboxItem,
  ContextMenuContent,
  ContextMenuGroup,
  ContextMenuItem,
  ContextMenuLabel,
  ContextMenuSeparator,
  ContextMenuSub,
  ContextMenuSubContent,
  ContextMenuSubTrigger,
  ContextMenuTrigger,
} from "@/components/ui/context-menu";
import { Kbd, KbdGroup } from "@/components/ui/kbd";
import { blockGroups, rowNote } from "@/lib/create";
import {
  APP_MODULE,
  connect,
  deleteColumn,
  isAppTable,
  userConnection,
} from "@/lib/design";

import { useCanvasBridge } from "./canvas-bridge";
import { useIsApplePlatform } from "./canvas-toolbar";
import { useDesign } from "./design-provider";
import { useCanvasActions } from "./schema-nodes";

/** What was right-clicked. A pane point is on the canvas, in flow coordinates. */
type MenuTarget =
  | { readonly kind: "pane"; readonly point: Point }
  | { readonly kind: "table"; readonly id: string }
  | { readonly kind: "group"; readonly manifest: string }
  | { readonly kind: "edge"; readonly id: string };

type ConnectPreset = Parameters<typeof connect>[2];

/** The canvas view state and the actions the menus need beyond the node actions. */
export interface CanvasMenuValue {
  readonly state: {
    readonly data: SchemaData;
    readonly preset: ConnectPreset;
    readonly layout: SchemaLayout;
    readonly expanded: ReadonlySet<string>;
    readonly collapsed: ReadonlySet<string>;
    readonly softRefs: boolean;
    /** The table the canvas is focused on, if any. */
    readonly focused: string | null;
  };
  readonly actions: {
    readonly addAt: (kind: PrimitiveKind, point: Point) => void;
    /** Adds a foreign key, the same way as dragging a table's handle. */
    readonly connect: (source: string, target: string) => void;
    readonly focus: (id: string) => void;
    readonly find: (id: string) => void;
    readonly fit: () => void;
    readonly tidy: () => void;
    readonly setSoftRefs: (on: boolean) => void;
    readonly setAllCollapsed: (collapsed: boolean) => void;
    readonly selectTables: (ids: readonly string[]) => void;
    readonly undoToast: (message: string) => void;
  };
}

const CanvasMenuContext = createContext<CanvasMenuValue | null>(null);

function useCanvasMenu(): CanvasMenuValue {
  const value = use(CanvasMenuContext);

  if (value === null) {
    throw new Error("Canvas menus need a CanvasMenu.");
  }

  return value;
}

/** A disabled item's label with the reason under it. */
function Label({
  children,
  reason,
}: {
  children: ReactNode;
  reason?: string | undefined;
}): ReactElement {
  return reason === undefined ? (
    <span className="min-w-0 flex-1 truncate">{children}</span>
  ) : (
    <span className="flex min-w-0 flex-1 flex-col">
      <span className="truncate">{children}</span>
      <span className="text-xs text-muted-foreground">{reason}</span>
    </span>
  );
}

function Keys({ keys }: { keys: readonly string[] }): ReactElement {
  return (
    <KbdGroup className="ml-auto">
      {keys.map((key) => (
        <Kbd key={key}>{key}</Kbd>
      ))}
    </KbdGroup>
  );
}

function PaneItems({ point }: { point: Point }): ReactElement {
  const { state, actions } = useCanvasMenu();
  const { state: designState } = useDesign();
  const apple = useIsApplePlatform();
  const moved = Object.keys(designState.design.positions ?? {}).length > 0;
  const groups = state.layout.groups.length;

  return (
    <>
      <ContextMenuGroup>
        <ContextMenuItem
          onClick={() => {
            actions.addAt("table", point);
          }}
        >
          <TableIcon aria-hidden="true" />
          <Label>Add table here</Label>
        </ContextMenuItem>
        <ContextMenuItem
          onClick={() => {
            actions.addAt("lookup", point);
          }}
        >
          <ListIcon aria-hidden="true" />
          <Label>Add lookup table here</Label>
        </ContextMenuItem>
      </ContextMenuGroup>
      <ContextMenuSeparator />
      <ContextMenuGroup>
        <ContextMenuItem onClick={actions.fit}>
          <MaximizeIcon aria-hidden="true" />
          <Label>Zoom to fit</Label>
          <Keys keys={[apple ? "⇧" : "Shift", "1"]} />
        </ContextMenuItem>
        <ContextMenuItem disabled={!moved} onClick={actions.tidy}>
          <LayoutGridIcon aria-hidden="true" />
          <Label reason={moved ? undefined : "No table has moved yet"}>
            Auto layout
          </Label>
        </ContextMenuItem>
        <ContextMenuCheckboxItem
          checked={state.softRefs}
          onCheckedChange={actions.setSoftRefs}
        >
          <SplineIcon aria-hidden="true" />
          <Label>Show soft references</Label>
        </ContextMenuCheckboxItem>
      </ContextMenuGroup>
      <ContextMenuSeparator />
      <ContextMenuGroup>
        <ContextMenuItem
          disabled={state.collapsed.size === 0}
          onClick={() => {
            actions.setAllCollapsed(false);
          }}
        >
          <UnfoldVerticalIcon aria-hidden="true" />
          <Label
            reason={
              state.collapsed.size === 0 ? "Every group is open" : undefined
            }
          >
            Expand all groups
          </Label>
        </ContextMenuItem>
        <ContextMenuItem
          disabled={state.collapsed.size >= groups}
          onClick={() => {
            actions.setAllCollapsed(true);
          }}
        >
          <FoldVerticalIcon aria-hidden="true" />
          <Label
            reason={
              state.collapsed.size >= groups
                ? "Every group is closed"
                : undefined
            }
          >
            Collapse all groups
          </Label>
        </ContextMenuItem>
      </ContextMenuGroup>
    </>
  );
}

const AUTH_USERS = "auth.users";

function ConnectTargets({ table }: { table: SchemaTable }): ReactElement {
  const { state, actions } = useCanvasMenu();
  const { state: designState } = useDesign();

  const options = [
    ...state.data.tables.filter((each) => each.id !== table.id),
  ].map((target) => ({
    id: target.id,
    label: target.name,
    app: isAppTable(target),
    result: connect(designState.design, state.data, state.preset, {
      source: table.id,
      target: target.id,
    }),
  }));

  const auth = connect(designState.design, state.data, state.preset, {
    source: table.id,
    target: AUTH_USERS,
  });

  const sections = [
    { title: "Your tables", items: options.filter((option) => option.app) },
    { title: "Block tables", items: options.filter((option) => !option.app) },
    {
      title: "Supabase",
      items: [{ id: AUTH_USERS, label: AUTH_USERS, app: false, result: auth }],
    },
  ].filter((section) => section.items.length > 0);

  return (
    <>
      {sections.map((section, index) => (
        <ContextMenuGroup key={section.title}>
          {index > 0 ? <ContextMenuSeparator /> : null}
          <ContextMenuLabel>{section.title}</ContextMenuLabel>
          {section.items.map((option) => (
            <ContextMenuItem
              key={option.id}
              disabled={!option.result.ok}
              onClick={() => {
                actions.connect(table.id, option.id);
              }}
            >
              <Label
                reason={option.result.ok ? undefined : option.result.error}
              >
                <span className="font-mono">{option.label}</span>
              </Label>
            </ContextMenuItem>
          ))}
        </ContextMenuGroup>
      ))}
    </>
  );
}

function TableItems({ id }: { id: string }): ReactElement | null {
  const { state, actions } = useCanvasMenu();
  const nodeActions = useCanvasActions();
  const table = state.data.tables.find((each) => each.id === id);

  if (table === undefined) {
    return null;
  }

  const app = isAppTable(table);
  const extendable = app || state.data.extraColumns.includes(id);
  const expanded = state.expanded.has(id);
  const hidden = state.layout.tables[id]?.rows.hidden ?? 0;
  const focused = state.focused === id;
  const appOnly = app ? undefined : "App tables only";

  return (
    <>
      <ContextMenuGroup>
        <ContextMenuItem
          onClick={() => {
            nodeActions.open(id);
          }}
        >
          <PanelRightOpenIcon aria-hidden="true" />
          <Label>Open details</Label>
          <Keys keys={["Enter"]} />
        </ContextMenuItem>
        <ContextMenuItem
          disabled={!extendable}
          onClick={() => {
            nodeActions.open(id, "columns");
          }}
        >
          <PlusIcon aria-hidden="true" />
          <Label
            reason={
              extendable ? undefined : "This block takes no extra columns"
            }
          >
            Add column
          </Label>
        </ContextMenuItem>
        {app ? (
          <ContextMenuSub>
            <ContextMenuSubTrigger className="gap-2">
              <ArrowRightIcon aria-hidden="true" />
              <Label>Add connection to…</Label>
            </ContextMenuSubTrigger>
            <ContextMenuSubContent className="max-h-80 w-60 shadow-lg">
              <ConnectTargets table={table} />
            </ContextMenuSubContent>
          </ContextMenuSub>
        ) : (
          <ContextMenuItem disabled>
            <ArrowRightIcon aria-hidden="true" />
            <Label reason="Only app tables can hold a foreign key">
              Add connection to…
            </Label>
          </ContextMenuItem>
        )}
        <ContextMenuItem
          disabled={!app}
          onClick={() => {
            nodeActions.open(id, "overview");
          }}
        >
          <PencilIcon aria-hidden="true" />
          <Label reason={appOnly}>Rename</Label>
        </ContextMenuItem>
        <ContextMenuItem
          disabled={!app}
          onClick={() => {
            nodeActions.duplicate(id);
          }}
        >
          <CopyIcon aria-hidden="true" />
          <Label reason={appOnly}>Duplicate</Label>
        </ContextMenuItem>
      </ContextMenuGroup>
      <ContextMenuSeparator />
      <ContextMenuGroup>
        <ContextMenuItem
          disabled={!expanded && hidden === 0}
          onClick={() => {
            nodeActions.toggleExpand(id);
          }}
        >
          {expanded ? (
            <FoldVerticalIcon aria-hidden="true" />
          ) : (
            <UnfoldVerticalIcon aria-hidden="true" />
          )}
          <Label
            reason={
              !expanded && hidden === 0 ? "Every column shows" : undefined
            }
          >
            {expanded ? "Collapse columns" : "Expand columns"}
          </Label>
        </ContextMenuItem>
        <ContextMenuItem
          onClick={() => {
            actions.focus(id);
          }}
        >
          <FocusIcon aria-hidden="true" />
          <Label>{focused ? "Leave focus" : "Focus on neighbours"}</Label>
          <Keys keys={["F"]} />
        </ContextMenuItem>
        <ContextMenuItem
          onClick={() => {
            void navigator.clipboard.writeText(id).then(
              () => toast.success(`Copied ${id}.`),
              () => toast.error("The clipboard is not available."),
            );
          }}
        >
          <ClipboardCopyIcon aria-hidden="true" />
          <Label>Copy name</Label>
        </ContextMenuItem>
      </ContextMenuGroup>
      <ContextMenuSeparator />
      <ContextMenuItem
        variant="destructive"
        disabled={!app}
        onClick={() => {
          nodeActions.requestDelete(id, true);
        }}
      >
        <Trash2Icon aria-hidden="true" />
        <Label reason={app ? undefined : "Block tables go with their block"}>
          Delete
        </Label>
        <Keys keys={["Delete"]} />
      </ContextMenuItem>
    </>
  );
}

/** App tables with a foreign key into a block's tables. */
function dependentsOf(design: Design, manifest: string): readonly string[] {
  return Object.entries(design.appTables ?? {})
    .filter(([, table]) =>
      Object.values(table.columns ?? {}).some(
        (column) => column.references?.block === manifest,
      ),
    )
    .map(([name]) => name);
}

function GroupItems({
  group,
  onRemove,
}: {
  group: LayoutGroup;
  onRemove: (manifest: string, dependents: readonly string[]) => void;
}): ReactElement {
  const { actions } = useCanvasMenu();
  const nodeActions = useCanvasActions();
  const { actions: bridge } = useCanvasBridge();
  const { state: designState } = useDesign();
  const { manifest } = group;
  const app = manifest === APP_MODULE;

  const row = blockGroups(designState.preset, resolvePreset(designState.preset))
    .flatMap((each) => each.rows)
    .find((each) => each.name === manifest);

  const required =
    row?.state.kind === "required" ? rowNote(row.state) : undefined;

  const notBlock = app
    ? "Your app tables are not a block"
    : row === undefined
      ? "Not a block you pick"
      : undefined;

  return (
    <>
      <ContextMenuGroup>
        <ContextMenuItem
          onClick={() => {
            nodeActions.toggleGroup(manifest);
          }}
        >
          {group.collapsed ? (
            <UnfoldVerticalIcon aria-hidden="true" />
          ) : (
            <FoldVerticalIcon aria-hidden="true" />
          )}
          <Label>{group.collapsed ? "Expand group" : "Collapse group"}</Label>
        </ContextMenuItem>
        <ContextMenuItem
          disabled={group.collapsed}
          onClick={() => {
            actions.selectTables(group.members);
          }}
        >
          <MousePointerClickIcon aria-hidden="true" />
          <Label
            reason={group.collapsed ? "Expand the group first" : undefined}
          >
            Select tables
          </Label>
        </ContextMenuItem>
        <ContextMenuItem
          disabled={notBlock !== undefined}
          onClick={() => {
            bridge.showBlock(manifest);
          }}
        >
          <PanelLeftIcon aria-hidden="true" />
          <Label reason={notBlock}>Show in options</Label>
        </ContextMenuItem>
      </ContextMenuGroup>
      <ContextMenuSeparator />
      <ContextMenuItem
        variant="destructive"
        disabled={notBlock !== undefined || required !== undefined}
        onClick={() => {
          onRemove(manifest, dependentsOf(designState.design, manifest));
        }}
      >
        <Trash2Icon aria-hidden="true" />
        <Label reason={notBlock ?? required}>Remove the block</Label>
      </ContextMenuItem>
    </>
  );
}

function EdgeItems({ edge }: { edge: LayoutEdge }): ReactElement {
  const { state, actions } = useCanvasMenu();
  const { state: designState, actions: designActions } = useDesign();

  const nameOf = (id: string): string =>
    state.data.tables.find((table) => table.id === id)?.name ?? id;

  // A layout edge runs from the referenced table to the one holding the key.
  const user =
    edge.kind === "foreign"
      ? userConnection(designState.design, edge.target, edge.targetColumn)
      : undefined;

  const reason =
    edge.kind === "soft"
      ? "A soft reference has no foreign key"
      : user === undefined
        ? "Part of a block"
        : undefined;

  return (
    <>
      <ContextMenuGroup>
        {[edge.target, edge.source].map((id) => (
          <ContextMenuItem
            key={id}
            onClick={() => {
              actions.find(id);
            }}
          >
            <ArrowRightIcon aria-hidden="true" />
            <Label>
              Go to <span className="font-mono">{nameOf(id)}</span>
            </Label>
          </ContextMenuItem>
        ))}
      </ContextMenuGroup>
      <ContextMenuSeparator />
      <ContextMenuItem
        variant="destructive"
        disabled={user === undefined}
        onClick={() => {
          if (user !== undefined) {
            designActions.apply(
              deleteColumn(designState.design, user.table, user.column),
            );
            actions.undoToast(`Removed ${user.column} from ${user.table}.`);
          }
        }}
      >
        <Trash2Icon aria-hidden="true" />
        <Label reason={reason}>Delete connection</Label>
      </ContextMenuItem>
    </>
  );
}

function MenuItems({
  target,
  onRemove,
}: {
  target: MenuTarget;
  onRemove: (manifest: string, dependents: readonly string[]) => void;
}): ReactElement | null {
  const { state } = useCanvasMenu();

  switch (target.kind) {
    case "pane": {
      return <PaneItems point={target.point} />;
    }

    case "table": {
      return <TableItems id={target.id} />;
    }

    case "group": {
      const group = state.layout.groups.find(
        (each) => each.manifest === target.manifest,
      );

      return group === undefined ? null : (
        <GroupItems group={group} onRemove={onRemove} />
      );
    }

    case "edge": {
      const edge = state.layout.edges.find((each) => each.id === target.id);

      return edge === undefined ? null : <EdgeItems edge={edge} />;
    }

    default: {
      const unreachable: never = target;

      return unreachable;
    }
  }
}

const IGNORED = ".react-flow__panel, .react-flow__minimap";

interface PendingRemove {
  readonly manifest: string;
  readonly dependents: readonly string[];
}

/**
 * One right-click menu for the whole canvas. Its items follow what was
 * clicked: the background, a table, a block group or a connection. Shift+F10
 * or the context-menu key on a focused table opens the same menu. Every
 * change goes through the design store, so Undo reverts it.
 */
export function CanvasMenu({
  value,
  children,
}: {
  value: CanvasMenuValue;
  /** The canvas element, which becomes the trigger. */
  children: ReactElement;
}): ReactElement {
  const flow = useReactFlow();
  const nodeActions = useCanvasActions();
  const [target, setTarget] = useState<MenuTarget | null>(null);

  const [pendingRemove, setPendingRemove] = useState<PendingRemove | null>(
    null,
  );

  const remove = (manifest: string): void => {
    nodeActions.removeBlock(manifest);
    value.actions.undoToast(`Removed the ${manifest} block.`);
  };

  const pick = (
    event: MouseEvent<HTMLElement> & { preventBaseUIHandler: () => void },
  ): void => {
    const element = event.target instanceof Element ? event.target : null;

    if (element?.closest(IGNORED) !== null && element !== null) {
      event.preventBaseUIHandler();

      return;
    }

    const node = element?.closest<HTMLElement>(".react-flow__node");
    const edge = element?.closest<HTMLElement>(".react-flow__edge");
    const id = node?.dataset["id"] ?? edge?.dataset["id"];

    if (node?.classList.contains("react-flow__node-table") && id) {
      setTarget({ kind: "table", id });
    } else if (node?.classList.contains("react-flow__node-blockGroup") && id) {
      const group = value.state.layout.groups.find((each) => each.id === id);

      setTarget(
        group === undefined
          ? null
          : { kind: "group", manifest: group.manifest },
      );
    } else if (edge !== null && edge !== undefined && id) {
      setTarget({ kind: "edge", id });
    } else {
      setTarget({
        kind: "pane",
        point: flow.screenToFlowPosition({
          x: event.clientX,
          y: event.clientY,
        }),
      });
    }
  };

  const onKeyDown = (event: KeyboardEvent<HTMLElement>): void => {
    const node =
      event.target instanceof HTMLElement &&
      event.target.matches(".react-flow__node")
        ? event.target
        : undefined;

    if (
      node === undefined ||
      !(event.key === "ContextMenu" || (event.shiftKey && event.key === "F10"))
    ) {
      return;
    }

    event.preventDefault();

    const box = node.getBoundingClientRect();

    node.dispatchEvent(
      new window.MouseEvent("contextmenu", {
        bubbles: true,
        cancelable: true,
        clientX: box.left + Math.min(box.width / 2, 48),
        clientY: box.top + 18,
      }),
    );
  };

  return (
    <CanvasMenuContext value={value}>
      <ContextMenu>
        <ContextMenuTrigger
          render={children}
          onContextMenu={pick}
          onKeyDown={onKeyDown}
        />
        <ContextMenuContent className="w-64">
          {target === null ? null : (
            <MenuItems
              target={target}
              onRemove={(manifest, dependents) => {
                if (dependents.length === 0) {
                  remove(manifest);
                } else {
                  setPendingRemove({ manifest, dependents });
                }
              }}
            />
          )}
        </ContextMenuContent>
      </ContextMenu>
      <AlertDialog
        open={pendingRemove !== null}
        onOpenChange={(next) => {
          if (!next) {
            setPendingRemove(null);
          }
        }}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              Remove the {pendingRemove?.manifest} block?
            </AlertDialogTitle>
            <AlertDialogDescription>
              {pendingRemove?.dependents.join(", ")}{" "}
              {pendingRemove?.dependents.length === 1
                ? "references"
                : "reference"}{" "}
              its tables. Those columns will point at tables the preset no
              longer installs until you remove them or add the block back.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              variant="destructive"
              onClick={() => {
                if (pendingRemove !== null) {
                  remove(pendingRemove.manifest);
                }

                setPendingRemove(null);
              }}
            >
              Remove
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </CanvasMenuContext>
  );
}
