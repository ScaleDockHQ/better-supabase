import { describe, expect, it } from "vitest";

import type { Result } from "../../../src/core/result.ts";

import { err, ok } from "../../../src/core/result.ts";
import {
  csvCell,
  exportListCsv,
  pageFromIds,
} from "../../../src/list/export/index.ts";

interface Row {
  readonly id: string;
  readonly name: string;
}

const rows: Row[] = Array.from({ length: 5 }, (_, at) => ({
  id: `r${String(at + 1)}`,
  name: `Row ${String(at + 1)}`,
}));

const pager =
  (all: readonly Row[], calls: (string | undefined)[] = []) =>
  (
    after: string | undefined,
    size: number,
  ): Promise<
    Result<{
      items: readonly Row[];
      nextCursor: string | null;
      hasMore: boolean;
    }>
  > => {
    calls.push(after);

    const start = after === undefined ? 0 : Number(after);
    const items = all.slice(start, start + size);
    const hasMore = start + size < all.length;

    return Promise.resolve(
      ok({ items, nextCursor: hasMore ? String(start + size) : null, hasMore }),
    );
  };

const columns = [
  { header: "id", value: (row: Row) => row.id },
  { header: "name", value: (row: Row) => row.name },
];

describe("csvCell", () => {
  it("quotes what needs it and defuses formulas", () => {
    expect(csvCell('say "hi", ok')).toBe('"say ""hi"", ok"');
    expect(csvCell("=SUM(A1)")).toBe("'=SUM(A1)");
    expect(csvCell(-5)).toBe("-5");
    expect(csvCell(null)).toBe("");
    expect(csvCell(new Date("2026-01-02T03:04:05Z"))).toBe(
      "2026-01-02T03:04:05.000Z",
    );
    expect(csvCell({ a: 1 })).toBe('"{""a"":1}"');
  });
});

describe("exportListCsv", () => {
  it("writes a header and every page, reading pages as the stream is read", async () => {
    const calls: (string | undefined)[] = [];

    const response = await exportListCsv({
      page: pager(rows, calls),
      columns,
      pageSize: 2,
      filename: 'a "b".csv',
    });

    expect(response.headers.get("content-type")).toBe(
      "text/csv; charset=utf-8",
    );
    expect(response.headers.get("content-disposition")).toBe(
      'attachment; filename="a_b_.csv"',
    );
    expect(await response.text()).toBe(
      "id,name\r\nr1,Row 1\r\nr2,Row 2\r\nr3,Row 3\r\nr4,Row 4\r\nr5,Row 5\r\n",
    );
    expect(calls).toEqual([undefined, "2", "4"]);
  });

  it("ends the file at maxRows", async () => {
    const response = await exportListCsv({
      page: pager(rows),
      columns,
      pageSize: 2,
      maxRows: 3,
    });

    expect((await response.text()).trim().split("\r\n")).toHaveLength(4);
  });

  it("returns the error of the first page as the response", async () => {
    const response = await exportListCsv({
      page: () =>
        Promise.resolve(
          err({ kind: "forbidden", message: "no", status: 403 } as never),
        ),
      columns,
    });

    expect(response.status).toBe(403);
  });
});

describe("exportListCsv edges", () => {
  it("starts with a byte order mark and falls back to a file name", async () => {
    const response = await exportListCsv({
      page: pager(rows.slice(0, 1)),
      columns,
      bom: true,
      filename: "",
    });

    expect(response.headers.get("content-disposition")).toContain(
      'filename="export.csv"',
    );
    expect([
      ...new Uint8Array(await response.arrayBuffer()).slice(0, 3),
    ]).toEqual([0xef, 0xbb, 0xbf]);
  });

  it("closes the stream when maxRows is zero, and clamps the page size", async () => {
    const calls: (string | undefined)[] = [];

    const response = await exportListCsv({
      page: pager(rows, calls),
      columns,
      maxRows: 0,
      pageSize: 0,
    });

    expect(await response.text()).toBe("id,name\r\n");
    expect(calls).toEqual([undefined]);
  });

  it("errors the stream when a later page fails", async () => {
    let call = 0;

    const response = await exportListCsv({
      page: () => {
        call += 1;

        return Promise.resolve(
          call === 1
            ? ok({ items: rows.slice(0, 1), nextCursor: "1", hasMore: true })
            : err({ kind: "unknown", message: "boom", status: 500 } as never),
        );
      },
      columns,
    });

    await expect(response.text()).rejects.toThrow("boom");
  });

  it("writes other values as text", () => {
    class Money {
      public toString(): string {
        return "EUR 5";
      }
    }

    expect(csvCell(new Money())).toBe("EUR 5");
    expect(csvCell([1, 2])).toBe('"[1,2]"');
    expect(csvCell(true)).toBe("true");
    expect(csvCell("plain")).toBe("plain");
    expect(csvCell(undefined)).toBe("");
  });
});

describe("pageFromIds", () => {
  const load =
    (hidden: readonly string[] = []) =>
    (ids: readonly string[]): Promise<Result<readonly Row[]>> =>
      Promise.resolve(
        ok(
          rows
            .filter((row) => ids.includes(row.id) && !hidden.includes(row.id))
            .toReversed(),
        ),
      );

  it("returns rows in the order of the ids and drops hidden ones", async () => {
    const page = await pageFromIds({
      ids: Promise.resolve(
        ok({ ids: ["r3", "r1", "r2"], nextCursor: "c", hasMore: true }),
      ),
      rows: load(["r1"]),
      idOf: (row) => row.id,
    }).orThrow();

    expect(page.items.map((row) => row.id)).toEqual(["r3", "r2"]);
    expect(page).toMatchObject({ nextCursor: "c", hasMore: true });
  });

  it("does not load rows for an empty page", async () => {
    const page = await pageFromIds({
      ids: Promise.resolve(ok({ ids: [], nextCursor: null, hasMore: false })),
      rows: () => {
        throw new Error("not called");
      },
      idOf: (row: Row) => row.id,
    }).orThrow();

    expect(page.items).toEqual([]);
  });
});
