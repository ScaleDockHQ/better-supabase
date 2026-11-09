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

  it("rebuilds the same today balance the replay uses", () => {
    const rebuild = sql.slice(sql.indexOf('"rebuild_open_items"'));

    expect(rebuild).toContain("paid_total");
    expect(rebuild).toContain("credited_total");
  });
});
