"use client";

import type { ReactElement } from "react";

import { ListIcon, TableIcon } from "lucide-react";

import {
  PRIMITIVE_DRAG_TYPE,
  PRIMITIVES,
  type PrimitiveKind,
} from "@/lib/primitives";
import { cn } from "@/lib/utils";

import { useCanvasBridge } from "./canvas-bridge";

export const PRIMITIVE_ICONS = {
  table: TableIcon,
  lookup: ListIcon,
} satisfies Readonly<Record<PrimitiveKind, typeof TableIcon>>;

/**
 * App tables to start from. Drag one onto the canvas to put it there, or
 * click it (or press Enter) to add it in the middle of the view. Each add is
 * one undo step.
 */
export function PrimitivePicker(): ReactElement {
  const { state } = useCanvasBridge();
  const { commands } = state;

  return (
    <div className="flex flex-col gap-2">
      <p className="text-xs text-muted-foreground">
        {commands === null
          ? "Pick a block first: primitives go on the canvas."
          : "Drag onto the canvas, or click to add in the middle of the view."}
      </p>
      <ul className="flex flex-col gap-0.5">
        {PRIMITIVES.map((primitive) => {
          const Icon = PRIMITIVE_ICONS[primitive.kind];

          return (
            <li key={primitive.kind}>
              <button
                type="button"
                draggable={commands !== null}
                disabled={commands === null}
                onDragStart={(event) => {
                  event.dataTransfer.setData(
                    PRIMITIVE_DRAG_TYPE,
                    primitive.kind,
                  );
                  event.dataTransfer.setData("text/plain", primitive.title);
                  event.dataTransfer.effectAllowed = "copy";
                }}
                onClick={() => {
                  commands?.addPrimitive(primitive.kind);
                }}
                className={cn(
                  "flex w-full items-start gap-2 rounded-md px-2 py-1.5 text-left text-sm transition-colors outline-none focus-visible:ring-3 focus-visible:ring-ring/50",
                  commands === null
                    ? "cursor-not-allowed opacity-50"
                    : "cursor-grab hover:bg-muted/60 active:cursor-grabbing",
                )}
              >
                <Icon
                  aria-hidden="true"
                  className="mt-0.5 size-4 shrink-0 text-muted-foreground"
                />
                <span className="flex min-w-0 flex-col">
                  <span className="leading-5">{primitive.title}</span>
                  <span className="text-xs leading-5 text-muted-foreground">
                    {primitive.description}
                  </span>
                </span>
              </button>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
