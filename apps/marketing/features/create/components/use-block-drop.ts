"use client";

import type { DragEvent } from "react";

import { useReactFlow } from "@xyflow/react";
import { resolvePreset } from "better-supabase/preset";
import { useCallback, useEffect, useRef } from "react";
import { toast } from "sonner";

import type { SchemaData } from "@/lib/schema";
import type { SchemaLayout } from "@/lib/schema-layout";

import { BLOCK_DRAG_TYPE, dropBlock } from "@/lib/create";
import { placeTables } from "@/lib/design";

import { useDesign } from "./design-provider";

/** Where a dropped block goes once its tables have a layout. */
interface Placement {
  readonly point: { readonly x: number; readonly y: number };
  readonly before: ReadonlySet<string>;
  readonly data: SchemaData;
}

export interface BlockDropTarget {
  readonly onDragOver: (event: DragEvent<HTMLElement>) => void;
  readonly onDrop: (event: DragEvent<HTMLElement>) => void;
}

/**
 * Turns on a block dragged from the side menu, like its switch, and puts
 * its new tables at the drop point. `data` is the schema the canvas has
 * now; `drawn` and `tables` are the schema and layout on screen, which
 * catch up after the schema request.
 */
export function useBlockDrop(
  data: SchemaData,
  drawn: SchemaData,
  tables: SchemaLayout["tables"],
  undoToast: (message: string) => void,
): BlockDropTarget {
  const { state, actions } = useDesign();
  const flow = useReactFlow();
  const placement = useRef<Placement | null>(null);
  const { design, preset } = state;

  const dropAt = useCallback(
    (name: string, client: { x: number; y: number }) => {
      const outcome = dropBlock(preset, resolvePreset(preset), name);

      switch (outcome.kind) {
        case "add": {
          placement.current = {
            point: flow.screenToFlowPosition(client),
            before: new Set(data.tables.map((table) => table.id)),
            data,
          };

          actions.setPreset(() => outcome.preset);
          undoToast(`Added the ${name} block.`);
          break;
        }

        case "installed": {
          toast(`The ${name} block is already on the canvas.`);
          break;
        }

        case "conflict": {
          toast.error(`The ${name} block can't be added: ${outcome.reason}`);
          break;
        }

        case "unknown": {
          break;
        }

        default: {
          const unreachable: never = outcome;

          return unreachable;
        }
      }
    },
    [actions, data, flow, preset, undoToast],
  );

  // The drop point waits for the new tables' layout, then joins the step
  // that added the block.
  useEffect(() => {
    const pending = placement.current;

    if (pending === null || drawn === pending.data) {
      return;
    }

    placement.current = null;

    const fresh = Object.fromEntries(
      Object.entries(tables).filter(([id]) => !pending.before.has(id)),
    );

    actions.place(placeTables(design, fresh, pending.point));
  }, [actions, design, drawn, tables]);

  return {
    onDragOver: (event) => {
      if (event.dataTransfer.types.includes(BLOCK_DRAG_TYPE)) {
        event.preventDefault();
        event.dataTransfer.dropEffect = "copy";
      }
    },
    onDrop: (event) => {
      const name = event.dataTransfer.getData(BLOCK_DRAG_TYPE);

      if (name !== "") {
        event.preventDefault();
        dropAt(name, { x: event.clientX, y: event.clientY });
      }
    },
  };
}
