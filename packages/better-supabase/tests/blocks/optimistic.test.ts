import { describe, expect, it } from "vitest";

import {
  optimisticArchive,
  optimisticReorder,
  optimisticUpdate,
} from "../../src/blocks/optimistic.ts";

const rows = [
  { id: "a", title: "A" },
  { id: "b", title: "B" },
  { id: "c", title: "C" },
];

const ids = (data: unknown): string[] =>
  (Array.isArray(data) ? data : []).map((row: { id: string }) => row.id);

describe("optimisticUpdate", () => {
  const update = optimisticUpdate({
    reads: ["list"],
    target: (id: string, title: string) => ({ id, patch: { title } }),
  });

  it("patches the row of a list", () => {
    expect(update.apply({ data: rows, args: ["b", "Z"] })).toStrictEqual([
      rows[0],
      { id: "b", title: "Z" },
      rows[2],
    ]);
  });

  it("patches the row of a page and keeps the page's other fields", () => {
    expect(
      update.apply({ data: { items: rows, cursor: "x" }, args: ["a", "Z"] }),
    ).toStrictEqual({
      items: [{ id: "a", title: "Z" }, rows[1], rows[2]],
      cursor: "x",
    });
  });

  it("leaves data of another shape alone", () => {
    expect(
      update.apply({ data: { total: 3 }, args: ["a", "Z"] }),
    ).toStrictEqual({ total: 3 });
  });
});

describe("optimisticArchive", () => {
  const archive = optimisticArchive({
    reads: ["list"],
    key: "id",
    target: (id: string, archived?: boolean) => ({ id, archived }),
  });

  it("takes the row out of the list", () => {
    expect(ids(archive.apply({ data: rows, args: ["b"] }))).toStrictEqual([
      "a",
      "c",
    ]);
  });

  it("keeps the list for a restore", () => {
    expect(archive.apply({ data: rows, args: ["b", false] })).toBe(rows);
  });
});

describe("optimisticReorder", () => {
  const reorder = optimisticReorder({
    reads: ["list"],
    target: (id: string, beforeId?: string) => ({ id, beforeId }),
  });

  it("moves the row before another", () => {
    expect(ids(reorder.apply({ data: rows, args: ["c", "a"] }))).toStrictEqual([
      "c",
      "a",
      "b",
    ]);
  });

  it("moves the row to the end without a target", () => {
    expect(ids(reorder.apply({ data: rows, args: ["a"] }))).toStrictEqual([
      "b",
      "c",
      "a",
    ]);
  });

  it("keeps the list when the row or the target is missing", () => {
    expect(reorder.apply({ data: rows, args: ["zz"] })).toBe(rows);
    expect(reorder.apply({ data: rows, args: ["a", "zz"] })).toBe(rows);
  });
});
