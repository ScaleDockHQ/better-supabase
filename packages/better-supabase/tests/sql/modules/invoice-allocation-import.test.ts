import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

describe("invoice allocation import", () => {
  const sql = renderBlocks(["invoices"])
    .map((file) => file.contents)
    .join("\n");

  it("links a receipt without posting a ledger entry", () => {
    const start = sql.indexOf('"allocate_existing"');
    const body = sql.slice(start, sql.indexOf('"import_allocation"', start));

    expect(body).toContain("'import'");
    expect(body).not.toContain("ledger_post");
    expect(body).not.toContain("record_invoice_payment");
    expect(sql).toContain("import_allocation");
    expect(sql).toContain("'import'");
  });
});
