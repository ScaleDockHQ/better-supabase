import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

describe("maintained open items", () => {
  const sql = renderBlocks(["invoices", "ledger"])
    .map((file) => file.contents)
    .join("\n");

  it("keeps today's balances in a table and replays past dates", () => {
    expect(sql).toContain(
      'create table "better_supabase"."invoice_open_items"',
    );
    expect(sql).toContain("invoice_open_items_party_idx");
    expect(sql).toContain("invoice_open_items_due_idx");
    expect(sql).toContain("rebuild_open_items");
    expect(sql).toContain("if v_as_of = current_date then");
    expect(sql).toContain("paid_total");

    const today = sql.slice(sql.indexOf("if v_as_of = current_date then"));
    const replay = today.slice(today.indexOf("end if;"));

    expect(today).toContain("invoice_open_items");
    expect(today).toContain("unallocated_payment");
    expect(replay).toContain("as_of");
  });

  it("pages the stored table and caps the total", () => {
    const body = sql.slice(
      sql.indexOf('"open_items_page"'),
      sql.indexOf('"open_items_for_party"'),
    );

    expect(body).toContain("limit least(");
    expect(body).toContain("offset greatest(");
    expect(body).toContain(
      "least(v_total, coalesce(open_items_page.count_cap, 10000))",
    );
    expect(body).not.toContain("effective_at");
  });

  it("rebuilds the same today balance the replay uses", () => {
    const rebuild = sql.slice(sql.indexOf('"rebuild_open_items"'));

    expect(rebuild).toContain("paid_total");
    expect(rebuild).toContain("credited_total");
  });
});
