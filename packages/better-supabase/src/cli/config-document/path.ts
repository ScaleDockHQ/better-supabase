import type { PathSegment } from "./document.ts";

/**
 * A dotted path as segments: `blocks.tasks.sameTenant[1]` is `blocks`, `tasks`,
 * `sameTenant` and the index `1`.
 */
export function parsePath(path: string): PathSegment[] {
  return [...path.matchAll(/([^.[\]]+)|\[(\d+)\]/g)].map((match) =>
    match[2] === undefined ? match[1]! : Number(match[2]),
  );
}
