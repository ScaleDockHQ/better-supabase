import type { NodeChange, XYPosition } from "@xyflow/react";

import type { LayoutGroup } from "@/lib/schema-layout";

import type { SchemaNode } from "./schema-nodes";

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
