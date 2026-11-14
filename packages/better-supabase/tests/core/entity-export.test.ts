import { describe, expect, it } from "vitest";

import type { PageOptions } from "../../src/core/block-helpers.ts";

import { exportCsv, exportResponse } from "../../src/core/entity-export.ts";
import { dbError } from "../../src/core/errors.ts";
import { AsyncResult } from "../../src/core/result.ts";

const rows = Array.from({ length: 5 }, (_, i) => ({
  id: String(i),
  title: i === 2 ? "=SUM(A1)" : `Row ${String(i)}`,
}));

function pager(seen: PageOptions[] = []) {
  return (options: PageOptions) => {
    seen.push(options);
    const start = Number(options.after?.[0] ?? 0);
    const limit = options.limit ?? 200;
    const items = rows.slice(start, start + limit);

    return AsyncResult.ok({
      items,
      hasMore: start + limit < rows.length,
      nextCursor: start + limit < rows.length ? [String(start + limit)] : null,
    });
  };
}

async function read(stream: ReadableStream<string>): Promise<string> {
  let text = "";

  for await (const chunk of stream) {
    text += chunk;
  }

  return text;
}

describe("exportCsv", () => {
  it("writes one header and every page", async () => {
    const seen: PageOptions[] = [];

    const text = await read(
      exportCsv(pager(seen), {
        pageSize: 2,
        filters: { status: ["open"] },
        q: "x",
      }),
    );

    expect(text.split("\r\n")).toEqual([
      "id,title",
      "0,Row 0",
      "1,Row 1",
      "2,'=SUM(A1)",
      "3,Row 3",
      "4,Row 4",
      "",
    ]);
    expect(seen).toHaveLength(3);
    expect(seen[0]).toMatchObject({ filters: { status: ["open"] }, q: "x" });
    expect(seen[1]?.after).toEqual(["2"]);
  });

  it("uses the given columns for the header", async () => {
    const text = await read(exportCsv(pager(), { columns: ["title"] }));

    expect(text.startsWith("title\r\nRow 0")).toBe(true);
  });

  it("errors the stream when a page fails", async () => {
    const stream = exportCsv(() =>
      AsyncResult.err(dbError("timeout", "Too slow")),
    );

    await expect(read(stream)).rejects.toMatchObject({ kind: "timeout" });
  });

  it("stops at the row cap with EXPORT_ROW_CAP", async () => {
    await expect(
      read(exportCsv(pager(), { maxRows: 3, pageSize: 2 })),
    ).rejects.toMatchObject({ hint: "EXPORT_ROW_CAP" });
  });

  it("passes the filters of page to every call", async () => {
    const seen: PageOptions[] = [];

    await read(
      exportCsv(pager(seen), {
        q: "row",
        filters: { status: ["open"] },
        sort: { by: "id", direction: "asc" },
      }),
    );

    expect(seen[0]).toMatchObject({
      q: "row",
      filters: { status: ["open"] },
      sort: { by: "id", direction: "asc" },
    });
  });

  it("writes an empty row for an item that is not an object", async () => {
    const text = await read(
      exportCsv(() =>
        AsyncResult.ok({ items: [1], hasMore: false, nextCursor: null }),
      ),
    );

    expect(text).toContain("\r\n");
  });

  it("answers a route with text/csv", async () => {
    const response = exportResponse(pager(), 'my "file".csv');

    expect(response.headers.get("content-type")).toContain("text/csv");
    expect(response.headers.get("content-disposition")).toBe(
      'attachment; filename="my__file_.csv"',
    );
    expect((await response.text()).startsWith("id,title")).toBe(true);
  });

  it("keeps formulas as they are when escaping is off", async () => {
    const text = await read(exportCsv(pager(), { escapeFormulas: false }));

    expect(text).toContain("=SUM(A1)");
    expect(text).not.toContain("'=SUM(A1)");
  });
});
