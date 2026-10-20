import type { NodeChange, OnNodeDrag, XYPosition } from "@xyflow/react";
import type { Design } from "better-supabase/create";

import { useCallback, useEffect, useRef } from "react";

import type { LayoutGroup } from "@/lib/schema-layout";

import type { SchemaNode } from "./schema-nodes";

import { collapsedMoves, collapsedStarts } from "./canvas-drag";

interface CollapsedDrag {
  readonly id: string;
  readonly from: XYPosition;
  readonly starts: ReadonlyMap<string, XYPosition>;
}

interface CollapsedDragHandlers {
  readonly onNodeDragStart: OnNodeDrag<SchemaNode>;
  readonly onNodeDragStop: () => void;
  /** The table moves a collapsed group's drag makes. */
  readonly movesFor: (
    changes: readonly NodeChange<SchemaNode>[],
  ) => Record<string, readonly [number, number]>;
}

/**
 * Drags a collapsed group by moving the tables it hides, so the group stays
 * where it was dropped and its tables open there.
 */
export function useCollapsedDrag(input: {
  readonly nodes: readonly SchemaNode[];
  readonly groups: readonly LayoutGroup[];
  readonly positions: Design["positions"];
  readonly commitDrag: () => void;
}): CollapsedDragHandlers {
  const { nodes, groups, positions, commitDrag } = input;
  const shown = useRef(new Map<string, XYPosition>());
  const drag = useRef<CollapsedDrag | null>(null);

  useEffect(() => {
    for (const node of nodes) {
      if (node.type === "table") {
        shown.current.set(node.id, node.position);
      }
    }
  }, [nodes]);

  const onNodeDragStart = useCallback<OnNodeDrag<SchemaNode>>(
    (_event, node) => {
      const group = groups.find((each) => each.id === node.id);

      if (group === undefined || !group.collapsed) {
        drag.current = null;

        return;
      }

      const known = new Map(shown.current);

      for (const [id, [x, y]] of Object.entries(positions ?? {})) {
        known.set(id, { x, y });
      }

      drag.current = {
        id: node.id,
        from: node.position,
        starts: collapsedStarts(group.members, node.position, known),
      };
    },
    [groups, positions],
  );

  const onNodeDragStop = useCallback(() => {
    drag.current = null;
    commitDrag();
  }, [commitDrag]);

  const movesFor = useCallback((changes: readonly NodeChange<SchemaNode>[]) => {
    const current = drag.current;
    const moves: Record<string, readonly [number, number]> = {};

    if (current === null) {
      return moves;
    }

    for (const change of changes) {
      if (
        change.type === "position" &&
        change.id === current.id &&
        change.position !== undefined
      ) {
        Object.assign(
          moves,
          collapsedMoves(current.starts, {
            x: change.position.x - current.from.x,
            y: change.position.y - current.from.y,
          }),
        );
      }
    }

    return moves;
  }, []);

  return { onNodeDragStart, onNodeDragStop, movesFor };
}
