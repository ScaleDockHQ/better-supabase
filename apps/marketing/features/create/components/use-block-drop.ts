"use client";

import type { DragEvent } from "react";

import { useReactFlow } from "@xyflow/react";
import { resolvePreset } from "better-supabase/preset";
import { useCallback } from "react";
import { toast } from "sonner";

import type { Point } from "@/lib/schema-layout";

import { BLOCK_DRAG_TYPE, dropBlock } from "@/lib/create";
import {
  isPrimitiveKind,
  PRIMITIVE_DRAG_TYPE,
  type PrimitiveKind,
} from "@/lib/primitives";

import { useDesign } from "./design-provider";

export interface BlockDropTarget {
  readonly onDragOver: (event: DragEvent<HTMLElement>) => void;
  readonly onDrop: (event: DragEvent<HTMLElement>) => void;
}

const DRAG_TYPES = [BLOCK_DRAG_TYPE, PRIMITIVE_DRAG_TYPE];

/**
 * Takes what the side menu drags onto the canvas. A block turns on like its
 * switch and its new tables go to the drop point through `expect`; a
 * primitive goes to `onPrimitive` with the drop point on the canvas.
 */
export function useBlockDrop({
  expect,
  undoToast,
  onPrimitive,
}: {
  expect: (point: Point, manifest?: string) => void;
  undoToast: (message: string) => void;
  onPrimitive: (kind: PrimitiveKind, point: Point) => void;
}): BlockDropTarget {
  const { state, actions } = useDesign();
  const flow = useReactFlow();
  const { preset } = state;

  const dropAt = useCallback(
    (name: string, point: Point) => {
      const outcome = dropBlock(preset, resolvePreset(preset), name);

      switch (outcome.kind) {
        case "add": {
          expect(point, name);
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
    [actions, expect, preset, undoToast],
  );

  return {
    onDragOver: (event) => {
      if (DRAG_TYPES.some((type) => event.dataTransfer.types.includes(type))) {
        event.preventDefault();
        event.dataTransfer.dropEffect = "copy";
      }
    },
    onDrop: (event) => {
      const block = event.dataTransfer.getData(BLOCK_DRAG_TYPE);
      const primitive = event.dataTransfer.getData(PRIMITIVE_DRAG_TYPE);

      const point = flow.screenToFlowPosition({
        x: event.clientX,
        y: event.clientY,
      });

      if (block !== "") {
        event.preventDefault();
        dropAt(block, point);
      } else if (isPrimitiveKind(primitive)) {
        event.preventDefault();
        onPrimitive(primitive, point);
      }
    },
  };
}
