import type { NodeChange, XYPosition } from "@xyflow/react";

import type { LayoutGroup } from "@/lib/schema-layout";

import type { SchemaNode } from "./schema-nodes";

import { GROUP_PADDING, NODE_WIDTH } from "../../../lib/schema-layout";

/** Pixels the pointer moves before a press is a drag, not a click that opens the table. */
export const DRAG_THRESHOLD = 4;

/** A button, link or handle inside a node acts on its own instead of opening the table. */
export function isControl(target: EventTarget | null): boolean {
  return (
    target instanceof Element &&
    target.closest("button, a, .react-flow__handle") !== null
  );
}

/**
 * The position changes that carry each dragged group's tables along with
 * it, by the same offset as the group.
 */
export function groupFollowers(
  changes: readonly NodeChange<SchemaNode>[],
  positions: ReadonlyMap<string, XYPosition>,
  groups: readonly Pick<LayoutGroup, "id" | "members">[],
): NodeChange<SchemaNode>[] {
  const membersOf = new Map(groups.map((group) => [group.id, group.members]));
  const followers: NodeChange<SchemaNode>[] = [];

  for (const change of changes) {
    if (change.type !== "position" || change.position === undefined) {
      continue;
    }

    const from = positions.get(change.id);
    const members = membersOf.get(change.id);

    if (from === undefined || members === undefined) {
      continue;
    }

    const dx = change.position.x - from.x;
    const dy = change.position.y - from.y;

    for (const id of members) {
      const start = positions.get(id);

      if (start !== undefined) {
        followers.push({
          type: "position",
          id,
          position: { x: start.x + dx, y: start.y + dy },
        });
      }
    }
  }

  return followers;
}

const COLLAPSED_GAP = 24;

/**
 * Where each table of a collapsed group starts when the group is dragged.
 * The first table sits at the group's corner, the others keep their offset
 * from it when both positions are known, and a table never shown goes in a
 * row to the right.
 */
export function collapsedStarts(
  members: readonly string[],
  group: XYPosition,
  known: ReadonlyMap<string, XYPosition>,
): Map<string, XYPosition> {
  const anchor = {
    x: group.x + GROUP_PADDING.side,
    y: group.y + GROUP_PADDING.top,
  };

  const first = known.get(members[0] ?? "");
  const starts = new Map<string, XYPosition>();

  for (const [index, id] of members.entries()) {
    const at = known.get(id);

    starts.set(
      id,
      first !== undefined && at !== undefined
        ? { x: anchor.x + at.x - first.x, y: anchor.y + at.y - first.y }
        : { x: anchor.x + index * (NODE_WIDTH + COLLAPSED_GAP), y: anchor.y },
    );
  }

  return starts;
}

/** The table positions after a collapsed group moved by `delta`. */
export function collapsedMoves(
  starts: ReadonlyMap<string, XYPosition>,
  delta: XYPosition,
): Record<string, readonly [number, number]> {
  return Object.fromEntries(
    [...starts].map(([id, start]) => [
      id,
      [Math.round(start.x + delta.x), Math.round(start.y + delta.y)] as const,
    ]),
  );
}
