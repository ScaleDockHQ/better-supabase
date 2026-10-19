import { EMPTY_DESIGN, moveTables } from "better-supabase/create";
import { describe, expect, test } from "vitest";

import { freeSpot, settleTables } from "../../lib/canvas-place";
import { GROUP_PADDING } from "../../lib/schema-layout";

const rect = (x: number, y: number, width = 200, height = 100) => ({
  x,
  y,
  width,
  height,
});

type Rect = ReturnType<typeof rect>;

/** Whether `box` keeps the 24px gap from `other`. */
function clearOf(box: Rect, other: Rect | undefined): boolean {
  return (
    other === undefined ||
    box.x >= other.x + other.width + 24 ||
    box.x + box.width <= other.x - 24 ||
    box.y >= other.y + other.height + 24 ||
    box.y + box.height <= other.y - 24
  );
}

describe("freeSpot", () => {
  test("keeps the point when nothing is in the way", () => {
    expect(freeSpot({ width: 100, height: 100 }, { x: 0, y: 0 }, [])).toEqual({
      x: 0,
      y: 0,
    });
  });

  test("moves off an occupied rectangle with the gap", () => {
    const occupied = [rect(0, 0)];

    const spot = freeSpot(
      { width: 100, height: 100 },
      { x: 50, y: 20 },
      occupied,
    );

    expect(clearOf({ ...spot, width: 100, height: 100 }, occupied[0])).toBe(
      true,
    );
  });

  test("takes the nearest free side", () => {
    const spot = freeSpot({ width: 100, height: 40 }, { x: 0, y: 70 }, [
      rect(0, 0, 400, 100),
    ]);

    expect(spot).toEqual({ x: 0, y: 142 });
  });
});

describe("settleTables", () => {
  const known = new Set(["public.items"]);

  test("puts new tables at the point, clear of the others", () => {
    const placed = settleTables(
      EMPTY_DESIGN,
      { "public.items": rect(0, 0), "public.lookups": rect(500, 500) },
      {
        point: { x: 10, y: 10 },
        known,
        shown: { "public.items": { x: 0, y: 0 } },
        occupied: [rect(0, 0)],
      },
    );

    const [x = 0, y = 0] = placed.positions?.["public.lookups"] ?? [];

    const box = rect(
      x - GROUP_PADDING.side,
      y - GROUP_PADDING.top,
      200 + GROUP_PADDING.side * 2,
      100 + GROUP_PADDING.top + GROUP_PADDING.bottom,
    );

    expect(clearOf(box, rect(0, 0))).toBe(true);
  });

  test("keeps the arrangement of several new tables", () => {
    const placed = settleTables(
      EMPTY_DESIGN,
      { "a.one": rect(300, 300), "a.two": rect(600, 340) },
      { point: { x: 0, y: 0 }, known: new Set(), shown: {}, occupied: [] },
    );

    expect(placed.positions).toEqual({ "a.one": [0, 0], "a.two": [300, 40] });
  });

  test("pins tables the new layout moved, but not saved ones", () => {
    const saved = moveTables(EMPTY_DESIGN, { "a.saved": [5, 5] });

    const placed = settleTables(
      saved,
      {
        "a.moved": rect(900, 0),
        "a.still": rect(0, 400),
        "a.saved": rect(700, 700),
      },
      {
        point: { x: 0, y: 0 },
        known: new Set(["a.moved", "a.still", "a.saved"]),
        shown: {
          "a.moved": { x: 0, y: 0 },
          "a.still": { x: 0, y: 400 },
          "a.saved": { x: 5, y: 5 },
        },
        occupied: [],
      },
    );

    expect(placed.positions).toEqual({ "a.saved": [5, 5], "a.moved": [0, 0] });
  });

  test("returns the same design when nothing changes", () => {
    expect(
      settleTables(
        EMPTY_DESIGN,
        { "a.one": rect(0, 0) },
        {
          point: { x: 0, y: 0 },
          known: new Set(["a.one"]),
          shown: { "a.one": { x: 0, y: 0 } },
          occupied: [],
        },
      ),
    ).toBe(EMPTY_DESIGN);
  });
});
