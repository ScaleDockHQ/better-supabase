import { type Design, moveTables } from "better-supabase/create";

import { GROUP_PADDING, type LayoutRect, type Point } from "./schema-layout";

/** The space kept between a new table's group and its neighbours. */
const GAP = 24;

const STEP = 24;

const MAX_RINGS = 120;

function overlaps(a: LayoutRect, b: LayoutRect): boolean {
  return (
    a.x < b.x + b.width &&
    b.x < a.x + a.width &&
    a.y < b.y + b.height &&
    b.y < a.y + a.height
  );
}

/** The candidates `ring` steps away from `point`, nearest first. */
function ringAround(point: Point, ring: number): readonly Point[] {
  const spots: Point[] = [];

  for (let dx = -ring; dx <= ring; dx += 1) {
    for (let dy = -ring; dy <= ring; dy += 1) {
      if (Math.max(Math.abs(dx), Math.abs(dy)) === ring) {
        spots.push({ x: point.x + dx * STEP, y: point.y + dy * STEP });
      }
    }
  }

  return spots.toSorted(
    (a, b) =>
      Math.hypot(a.x - point.x, a.y - point.y) -
      Math.hypot(b.x - point.x, b.y - point.y),
  );
}

/**
 * The top-left corner nearest to `point` where a box of `size` keeps `gap`
 * from every occupied rectangle, searched on a 24px grid. Falls back to
 * `point` when nothing within reach is free.
 */
export function freeSpot(
  size: { readonly width: number; readonly height: number },
  point: Point,
  occupied: readonly LayoutRect[],
  gap = GAP,
): Point {
  const fits = (spot: Point): boolean => {
    const box = {
      x: spot.x - gap,
      y: spot.y - gap,
      width: size.width + gap * 2,
      height: size.height + gap * 2,
    };

    return occupied.every((rect) => !overlaps(box, rect));
  };

  if (fits(point)) {
    return point;
  }

  for (let ring = 1; ring <= MAX_RINGS; ring += 1) {
    const spot = ringAround(point, ring).find(fits);

    if (spot !== undefined) {
      return spot;
    }
  }

  return point;
}

/** What the canvas showed when tables were added, to place them once the layout catches up. */
export interface PendingPlacement {
  /** Where the new tables' top-left corner should go. */
  readonly point: Point;
  /** The tables in the schema before the change: any other table is new. */
  readonly known: ReadonlySet<string>;
  /** Where each table was on screen. */
  readonly shown: Readonly<Record<string, Point>>;
  /** Every node rectangle the new tables must stay clear of. */
  readonly occupied: readonly LayoutRect[];
}

/**
 * Puts the new tables of a fresh layout at the free spot nearest to the
 * pending point, keeping their arrangement, and pins every table without a
 * saved position that the new layout moved back where it was on screen.
 * Tables with a saved position keep it.
 */
export function settleTables(
  design: Design,
  tables: Readonly<Record<string, LayoutRect>>,
  pending: PendingPlacement,
): Design {
  const moves: Record<string, readonly [number, number]> = {};

  for (const [id, was] of Object.entries(pending.shown)) {
    const now = tables[id];

    if (
      now !== undefined &&
      design.positions?.[id] === undefined &&
      (Math.round(now.x) !== Math.round(was.x) ||
        Math.round(now.y) !== Math.round(was.y))
    ) {
      moves[id] = [Math.round(was.x), Math.round(was.y)];
    }
  }

  const fresh = Object.entries(tables).filter(([id]) => !pending.known.has(id));

  if (fresh.length > 0) {
    const left = Math.min(...fresh.map(([, rect]) => rect.x));
    const top = Math.min(...fresh.map(([, rect]) => rect.y));
    const right = Math.max(...fresh.map(([, rect]) => rect.x + rect.width));
    const bottom = Math.max(...fresh.map(([, rect]) => rect.y + rect.height));

    const spot = freeSpot(
      {
        width: right - left + GROUP_PADDING.side * 2,
        height: bottom - top + GROUP_PADDING.top + GROUP_PADDING.bottom,
      },
      {
        x: pending.point.x - GROUP_PADDING.side,
        y: pending.point.y - GROUP_PADDING.top,
      },
      pending.occupied,
    );

    for (const [id, rect] of fresh) {
      moves[id] = [
        Math.round(rect.x - left + spot.x + GROUP_PADDING.side),
        Math.round(rect.y - top + spot.y + GROUP_PADDING.top),
      ];
    }
  }

  return Object.keys(moves).length === 0 ? design : moveTables(design, moves);
}
