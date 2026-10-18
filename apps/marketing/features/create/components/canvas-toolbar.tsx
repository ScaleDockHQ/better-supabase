"use client";

import type { ReactElement, Ref } from "react";

import { useReactFlow, useStore } from "@xyflow/react";
import {
  CrosshairIcon,
  DownloadIcon,
  EllipsisIcon,
  FilterIcon,
  Grid3x3Icon,
  KeyboardIcon,
  LayoutDashboardIcon,
  Link2OffIcon,
  MinusIcon,
  PlusIcon,
  Redo2Icon,
  RotateCcwIcon,
  SearchIcon,
  Undo2Icon,
} from "lucide-react";
import { useEffect, useRef, useState, useSyncExternalStore } from "react";

import { Button } from "@/components/ui/button";
import { ButtonGroup } from "@/components/ui/button-group";
import {
  DropdownMenu,
  DropdownMenuCheckboxItem,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuShortcut,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Input } from "@/components/ui/input";
import { Kbd, KbdGroup } from "@/components/ui/kbd";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import { Toggle } from "@/components/ui/toggle";
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import { FIT_PADDING } from "@/lib/schema-layout";

export const FIT_VIEW_OPTIONS = { padding: FIT_PADDING, maxZoom: 1 } as const;

// A shortcut never fires while a field, dialog or menu owns the keyboard.
const KEYBOARD_OWNERS =
  "input, textarea, select, [contenteditable='true'], [role='dialog'], [role='alertdialog'], [role='menu'], [role='listbox'], [role='combobox']";

export function isKeyboardOwned(target: EventTarget | null): boolean {
  return target instanceof Element && target.closest(KEYBOARD_OWNERS) !== null;
}

// The platform never changes while the page is open, so nothing to subscribe.
const subscribeToPlatform = (): (() => void) => () => {};

/** The server has no navigator, so it renders Mac keys and the client corrects. */
export function useIsApplePlatform(): boolean {
  return useSyncExternalStore(
    subscribeToPlatform,
    () => /Mac|iPhone|iPad/u.test(navigator.userAgent),
    () => true,
  );
}

export type ExportFormat = "png" | "svg" | "mermaid" | "dbml" | "json";

const EXPORTS: readonly {
  readonly format: ExportFormat;
  readonly label: string;
}[] = [
  { format: "png", label: "PNG image" },
  { format: "svg", label: "SVG image" },
  { format: "mermaid", label: "Mermaid diagram" },
  { format: "dbml", label: "DBML" },
  { format: "json", label: "JSON" },
];

export interface ToolbarTable {
  readonly id: string;
  readonly label: string;
}

export interface CanvasToolbarProps {
  readonly canUndo: boolean;
  readonly canRedo: boolean;
  readonly onUndo: () => void;
  readonly onRedo: () => void;
  readonly onAddTable: () => void;
  readonly onTidy: () => void;
  readonly hideSoftRefs: boolean;
  readonly onHideSoftRefs: (hide: boolean) => void;
  readonly snap: boolean;
  readonly onSnap: (on: boolean) => void;
  readonly focus: boolean;
  readonly canFocus: boolean;
  readonly onFocus: (on: boolean) => void;
  readonly tables: readonly ToolbarTable[];
  readonly onFind: (id: string) => void;
  readonly categories: readonly string[];
  readonly hiddenCategories: ReadonlySet<string>;
  readonly onCategory: (category: string, shown: boolean) => void;
  readonly onExport: (format: ExportFormat) => void;
  readonly onShortcuts: () => void;
  readonly canReset: boolean;
  readonly onReset: () => void;
}

function IconAction({
  label,
  keys,
  disabled,
  onClick,
  buttonRef,
  children,
}: {
  label: string;
  keys?: readonly string[];
  disabled?: boolean;
  onClick: () => void;
  buttonRef?: Ref<HTMLButtonElement>;
  children: ReactElement;
}): ReactElement {
  return (
    <Tooltip>
      <TooltipTrigger
        render={
          <Button
            ref={buttonRef}
            type="button"
            variant="outline"
            size="icon-sm"
            aria-label={label}
            disabled={disabled}
            onClick={onClick}
          />
        }
      >
        {children}
      </TooltipTrigger>
      <TooltipContent className="flex items-center gap-1.5">
        {label}
        {keys === undefined ? null : (
          <KbdGroup>
            {keys.map((key) => (
              <Kbd key={key}>{key}</Kbd>
            ))}
          </KbdGroup>
        )}
      </TooltipContent>
    </Tooltip>
  );
}

function ToggleAction({
  label,
  pressed,
  disabled,
  onPressed,
  children,
}: {
  label: string;
  pressed: boolean;
  disabled?: boolean;
  onPressed: (pressed: boolean) => void;
  children: ReactElement;
}): ReactElement {
  return (
    <Tooltip>
      <TooltipTrigger
        render={
          <Toggle
            variant="outline"
            size="sm"
            aria-label={label}
            pressed={pressed}
            disabled={disabled}
            onPressedChange={onPressed}
          />
        }
      >
        {children}
      </TooltipTrigger>
      <TooltipContent>{label}</TooltipContent>
    </Tooltip>
  );
}

function FindTable({
  tables,
  onFind,
}: Pick<CanvasToolbarProps, "tables" | "onFind">): ReactElement {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");

  const matches = tables.filter((table) =>
    table.label.toLowerCase().includes(query.trim().toLowerCase()),
  );

  return (
    <Popover
      open={open}
      onOpenChange={(next) => {
        setOpen(next);
        setQuery("");
      }}
    >
      <Tooltip>
        <TooltipTrigger
          render={
            <PopoverTrigger
              render={
                <Button
                  type="button"
                  variant="outline"
                  size="icon-sm"
                  aria-label="Search tables"
                />
              }
            />
          }
        >
          <SearchIcon aria-hidden="true" />
        </TooltipTrigger>
        <TooltipContent>Search tables</TooltipContent>
      </Tooltip>
      <PopoverContent align="start" className="w-64 gap-2">
        <Input
          aria-label="Table name"
          placeholder="Search tables"
          value={query}
          onChange={(event) => {
            setQuery(event.target.value);
          }}
          onKeyDown={(event) => {
            const first = matches[0];

            if (event.key === "Enter" && first !== undefined) {
              onFind(first.id);
              setOpen(false);
            }
          }}
        />
        {matches.length === 0 ? (
          <p className="px-1 text-xs text-muted-foreground">
            No table matches {query.trim()}.
          </p>
        ) : (
          <ul className="flex max-h-64 flex-col overflow-y-auto">
            {matches.map((table) => (
              <li key={table.id}>
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  className="w-full justify-start font-mono"
                  onClick={() => {
                    onFind(table.id);
                    setOpen(false);
                  }}
                >
                  {table.label}
                </Button>
              </li>
            ))}
          </ul>
        )}
      </PopoverContent>
    </Popover>
  );
}

/** The view and export actions, as menu items for the More menu on small screens. */
function MoreItems(props: CanvasToolbarProps): ReactElement {
  return (
    <>
      <DropdownMenuGroup>
        <DropdownMenuItem onClick={props.onTidy}>
          <LayoutDashboardIcon aria-hidden="true" />
          Tidy layout
        </DropdownMenuItem>
        <DropdownMenuCheckboxItem
          checked={props.hideSoftRefs}
          onCheckedChange={props.onHideSoftRefs}
        >
          Hide soft references
        </DropdownMenuCheckboxItem>
        <DropdownMenuCheckboxItem
          checked={props.snap}
          onCheckedChange={props.onSnap}
        >
          Snap to grid
        </DropdownMenuCheckboxItem>
        <DropdownMenuCheckboxItem
          checked={props.focus}
          disabled={!props.canFocus}
          onCheckedChange={props.onFocus}
        >
          Focus on the selected table
        </DropdownMenuCheckboxItem>
      </DropdownMenuGroup>
      <DropdownMenuSeparator />
      <DropdownMenuGroup>
        <DropdownMenuLabel>Export</DropdownMenuLabel>
        {EXPORTS.map((item) => (
          <DropdownMenuItem
            key={item.format}
            onClick={() => {
              props.onExport(item.format);
            }}
          >
            {item.label}
          </DropdownMenuItem>
        ))}
      </DropdownMenuGroup>
      <DropdownMenuSeparator />
      <DropdownMenuItem disabled={!props.canReset} onClick={props.onReset}>
        <RotateCcwIcon aria-hidden="true" />
        Reset to preset
      </DropdownMenuItem>
    </>
  );
}

/** Floats over the canvas, so the controls sit where the pointer already is. */
export function CanvasToolbar(props: CanvasToolbarProps): ReactElement {
  const { canUndo, canRedo, onUndo, onRedo } = props;
  const apple = useIsApplePlatform();
  const mod = apple ? "⌘" : "Ctrl";
  const shift = apple ? "⇧" : "Shift";
  const undoRef = useRef<HTMLButtonElement>(null);
  const redoRef = useRef<HTMLButtonElement>(null);
  const actedRef = useRef<"undo" | "redo" | null>(null);

  // Emptying a stack disables the button just pressed, which would drop focus
  // to the page, so focus moves to its counterpart instead.
  useEffect(() => {
    const acted = actedRef.current;
    actedRef.current = null;

    if (document.activeElement !== document.body) {
      return;
    }

    if (acted === "undo" && !canUndo) {
      redoRef.current?.focus();
    } else if (acted === "redo" && !canRedo) {
      undoRef.current?.focus();
    }
  }, [canRedo, canUndo]);

  return (
    <TooltipProvider delay={300}>
      <div
        role="toolbar"
        aria-label="Schema tools"
        className="flex flex-wrap items-center gap-2"
      >
        <ButtonGroup aria-label="Tables">
          <IconAction label="Add table" keys={["N"]} onClick={props.onAddTable}>
            <PlusIcon aria-hidden="true" />
          </IconAction>
          <FindTable tables={props.tables} onFind={props.onFind} />
        </ButtonGroup>
        <ButtonGroup aria-label="History">
          <IconAction
            label="Undo"
            keys={[mod, "Z"]}
            disabled={!canUndo}
            buttonRef={undoRef}
            onClick={() => {
              actedRef.current = "undo";
              onUndo();
            }}
          >
            <Undo2Icon aria-hidden="true" />
          </IconAction>
          <IconAction
            label="Redo"
            keys={[shift, mod, "Z"]}
            disabled={!canRedo}
            buttonRef={redoRef}
            onClick={() => {
              actedRef.current = "redo";
              onRedo();
            }}
          >
            <Redo2Icon aria-hidden="true" />
          </IconAction>
        </ButtonGroup>
        <ButtonGroup aria-label="View" className="hidden sm:flex">
          <IconAction label="Tidy layout" onClick={props.onTidy}>
            <LayoutDashboardIcon aria-hidden="true" />
          </IconAction>
          <ToggleAction
            label="Hide soft references"
            pressed={props.hideSoftRefs}
            onPressed={props.onHideSoftRefs}
          >
            <Link2OffIcon aria-hidden="true" />
          </ToggleAction>
          <ToggleAction
            label="Snap to grid"
            pressed={props.snap}
            onPressed={props.onSnap}
          >
            <Grid3x3Icon aria-hidden="true" />
          </ToggleAction>
          <ToggleAction
            label="Focus on the selected table"
            pressed={props.focus}
            disabled={!props.canFocus}
            onPressed={props.onFocus}
          >
            <CrosshairIcon aria-hidden="true" />
          </ToggleAction>
          <DropdownMenu>
            <Tooltip>
              <TooltipTrigger
                render={
                  <DropdownMenuTrigger
                    render={
                      <Button
                        type="button"
                        variant="outline"
                        size="icon-sm"
                        aria-label="Filter by category"
                      />
                    }
                  />
                }
              >
                <FilterIcon aria-hidden="true" />
              </TooltipTrigger>
              <TooltipContent>Filter by category</TooltipContent>
            </Tooltip>
            <DropdownMenuContent align="start" className="w-48">
              <DropdownMenuGroup>
                <DropdownMenuLabel>Categories</DropdownMenuLabel>
                {props.categories.map((category) => (
                  <DropdownMenuCheckboxItem
                    key={category}
                    checked={!props.hiddenCategories.has(category)}
                    onCheckedChange={(checked) => {
                      props.onCategory(category, checked);
                    }}
                  >
                    {category}
                  </DropdownMenuCheckboxItem>
                ))}
              </DropdownMenuGroup>
            </DropdownMenuContent>
          </DropdownMenu>
          <DropdownMenu>
            <Tooltip>
              <TooltipTrigger
                render={
                  <DropdownMenuTrigger
                    render={
                      <Button
                        type="button"
                        variant="outline"
                        size="icon-sm"
                        aria-label="Export"
                      />
                    }
                  />
                }
              >
                <DownloadIcon aria-hidden="true" />
              </TooltipTrigger>
              <TooltipContent>Export</TooltipContent>
            </Tooltip>
            <DropdownMenuContent align="start" className="w-48">
              <DropdownMenuGroup>
                <DropdownMenuLabel>Export</DropdownMenuLabel>
                {EXPORTS.map((item) => (
                  <DropdownMenuItem
                    key={item.format}
                    onClick={() => {
                      props.onExport(item.format);
                    }}
                  >
                    {item.label}
                  </DropdownMenuItem>
                ))}
              </DropdownMenuGroup>
            </DropdownMenuContent>
          </DropdownMenu>
          <IconAction
            label="Keyboard shortcuts"
            keys={["?"]}
            onClick={props.onShortcuts}
          >
            <KeyboardIcon aria-hidden="true" />
          </IconAction>
          <IconAction
            label="Reset to preset"
            disabled={!props.canReset}
            onClick={props.onReset}
          >
            <RotateCcwIcon aria-hidden="true" />
          </IconAction>
        </ButtonGroup>
        <DropdownMenu>
          <DropdownMenuTrigger
            render={
              <Button
                type="button"
                variant="outline"
                size="icon-sm"
                aria-label="More tools"
                className="sm:hidden"
              />
            }
          >
            <EllipsisIcon aria-hidden="true" />
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-56">
            <MoreItems {...props} />
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    </TooltipProvider>
  );
}

/** The zoom level and the zoom presets, in the bottom-right corner. */
export function ZoomControls(): ReactElement {
  const { fitView, zoomIn, zoomOut, zoomTo } = useReactFlow();
  // Only the zoom, so a pan never re-renders the controls.
  const zoom = useStore((state) => state.transform[2]);
  const minZoom = useStore((state) => state.minZoom);
  const maxZoom = useStore((state) => state.maxZoom);
  const percent = Math.round(zoom * 100);
  const apple = useIsApplePlatform();
  const shift = apple ? "⇧" : "Shift+";

  return (
    <ButtonGroup aria-label="Zoom">
      <Button
        type="button"
        variant="outline"
        size="icon-sm"
        aria-label="Zoom out"
        disabled={zoom <= minZoom}
        onClick={() => {
          void zoomOut();
        }}
      >
        <MinusIcon aria-hidden="true" />
      </Button>
      {/* Fixed width, so the bar never shifts as the value gains a digit. */}
      <DropdownMenu>
        <DropdownMenuTrigger
          render={
            <Button
              type="button"
              variant="outline"
              size="sm"
              aria-label={`Zoom level ${percent}%`}
              className="w-12 tabular-nums"
            />
          }
        >
          {percent}%
        </DropdownMenuTrigger>
        <DropdownMenuContent
          side="top"
          align="end"
          sideOffset={8}
          className="w-44"
        >
          <DropdownMenuItem
            onClick={() => {
              void fitView(FIT_VIEW_OPTIONS);
            }}
          >
            Zoom to fit
            <DropdownMenuShortcut>{shift}1</DropdownMenuShortcut>
          </DropdownMenuItem>
          <DropdownMenuSeparator />
          {[0.5, 1, 2].map((level) => (
            <DropdownMenuItem
              key={level}
              onClick={() => {
                void zoomTo(level);
              }}
            >
              Zoom to {level * 100}%
            </DropdownMenuItem>
          ))}
        </DropdownMenuContent>
      </DropdownMenu>
      <Button
        type="button"
        variant="outline"
        size="icon-sm"
        aria-label="Zoom in"
        disabled={zoom >= maxZoom}
        onClick={() => {
          void zoomIn();
        }}
      >
        <PlusIcon aria-hidden="true" />
      </Button>
    </ButtonGroup>
  );
}
