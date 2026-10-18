"use client";

import type { Node } from "@xyflow/react";

import { useReactFlow } from "@xyflow/react";
import { useCallback, useEffect, useRef } from "react";

import type { SchemaData } from "@/lib/schema";
import type { LayoutRect, Point, SchemaLayout } from "@/lib/schema-layout";

import { type PendingPlacement, settleTables } from "@/lib/canvas-place";
import { groupId } from "@/lib/schema-layout";

import { useDesign } from "./design-provider";

interface Pending extends PendingPlacement {
  /** The schemas drawn and current at the time, which the layout has to move past. */
  readonly seen: ReadonlySet<SchemaData>;
}

function rectOf(node: Node): LayoutRect {
  return {
    ...node.position,
    width: node.width ?? node.measured?.width ?? 0,
    height: node.height ?? node.measured?.height ?? 0,
  };
}

/**
 * Places the tables the next change adds. Call `expect` right before the
 * change with the top-left corner they should take and the group they join;
 * once the layout has them, they move to the nearest free spot and every
 * table the new layout moved goes back where it was, inside the step of the
 * change. `data` is the schema the canvas has now; `drawn` and `tables` are
 * the schema and layout on screen, which catch up after the change.
 */
export function usePlacement(
  data: SchemaData,
  drawn: SchemaData,
  tables: SchemaLayout["tables"],
): (point: Point, manifest?: string) => void {
  const { state, actions } = useDesign();
  const flow = useReactFlow();
  const pending = useRef<Pending | null>(null);
  const { design } = state;

  const expect = useCallback(
    (point: Point, manifest?: string) => {
      const nodes = flow.getNodes();
      const joins = manifest === undefined ? undefined : groupId(manifest);

      pending.current = {
        point,
        known: new Set(data.tables.map((table) => table.id)),
        shown: Object.fromEntries(
          nodes
            .filter((node) => node.type === "table")
            .map((node) => [node.id, node.position]),
        ),
        // The group the new tables join grows around them, so it isn't in the way.
        occupied: nodes.filter((node) => node.id !== joins).map(rectOf),
        seen: new Set([data, drawn]),
      };
    },
    [data, drawn, flow],
  );

  useEffect(() => {
    const current = pending.current;

    if (current === null || current.seen.has(drawn)) {
      return;
    }

    pending.current = null;
    actions.place(settleTables(design, tables, current));
  }, [actions, design, drawn, tables]);

  return expect;
}
