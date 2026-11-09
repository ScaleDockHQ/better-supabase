import { describe, expect, it } from "vitest";

import { withoutSkippedIndexes } from "../../src/sql/index-skip.ts";
import { renderBlocks } from "../../src/sql/render.ts";

const invoices = (skip?: readonly string[]): string =>
  renderBlocks(["invoices"], {
    modules: skip === undefined ? {} : { invoices: { indexes: { skip } } },
  })
    .filter((file) => file.module === "invoices" && file.kind === "schema")
    .map((file) => file.contents)
    .join("\n");

describe("blocks.indexes.skip", () => {
  it("leaves out a named index and keeps the others", () => {
    const sql = invoices(["invoices_tenant_status_idx"]);

    expect(sql).not.toContain("invoices_tenant_status_idx");
    expect(sql).toContain("invoice_charges_invoice_idx");
  });

  it("refuses a name the module does not create", () => {
    expect(() => invoices(["invoices_tenant_status_due"])).toThrow(
      /invoices_tenant_status_due/,
    );
  });

  it("does not drop an index name that only appears inside a function", () => {
    const sql = `
create index if not exists kept_idx on public.kept (id);
create function public.note() returns void language sql as $$
  select 1 where false;
$$;
`;

    const stripped = withoutSkippedIndexes(sql, new Set(["note"]));

    expect(stripped.removed).toEqual([]);
    expect(stripped.sql).toContain("kept_idx");
    expect(stripped.sql).toContain("function public.note");
  });
});
