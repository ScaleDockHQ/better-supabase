import { describe, expect, it } from "vitest";

import { csvColumns, csvResponse, toCsv } from "../../src/server/index.ts";

describe("csvResponse", () => {
  it("serves the rows as a CSV attachment", async () => {
    const response = csvResponse([{ a: "x", b: "=1" }], {
      filename: "rows.csv",
    });
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toBe(
      "text/csv; charset=utf-8",
    );
    expect(response.headers.get("content-disposition")).toBe(
      `attachment; filename="rows.csv"; filename*=UTF-8''rows.csv`,
    );
    expect(await response.text()).toBe("a,b\r\nx,'=1\r\n");
  });

  it("passes columns, escaping, status and headers through", async () => {
    const response = csvResponse([{ a: "=1", b: 2 }], {
      filename: 'café "q".csv',
      columns: ["b", "a"],
      escapeFormulas: false,
      status: 201,
      headers: { "cache-control": "no-store", "content-type": "text/plain" },
    });
    expect(response.status).toBe(201);
    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(response.headers.get("content-type")).toBe(
      "text/csv; charset=utf-8",
    );
    expect(response.headers.get("content-disposition")).toBe(
      `attachment; filename="caf_ _q_.csv"; filename*=UTF-8''caf%C3%A9%20%22q%22.csv`,
    );
    expect(await response.text()).toBe("b,a\r\n2,=1\r\n");
  });

  it("exports the helpers it is built from", () => {
    expect(csvColumns([{ a: 1 }, { b: 2 }])).toEqual(["a", "b"]);
    expect(toCsv([{ a: 1 }])).toBe("a\r\n1\r\n");
  });
});
