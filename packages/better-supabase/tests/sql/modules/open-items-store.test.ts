import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

describe("maintained open items", () => {
  const sql = renderBlocks(["invoices", "ledger"])
    .map((file) => file.contents)
    .join("\n");

  const between = (start: string, end: string): string =>
    sql.slice(sql.indexOf(start), sql.indexOf(end, sql.indexOf(start)));

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
    const stored = today.slice(0, today.indexOf("end if;"));
    const replay = today.slice(today.indexOf("end if;"));

    expect(stored).toContain("invoice_open_items");
    expect(stored).toContain("unallocated_payment");
    expect(stored).not.toContain("union all");
    expect(stored).toContain("<= v_as_of");
    expect(replay).toContain("as_of");
  });

  it("drops the invoice reference so unallocated rows fit", () => {
    const table = between(
      'create table "better_supabase"."invoice_open_items"',
      ");\n",
    );

    expect(table).not.toContain("references");
    expect(table).toContain("'unallocated_payment'");
  });

  it("refreshes on kind, party and charge changes and on credit balances", () => {
    expect(sql).toMatch(
      /after insert or delete or update of [^\n]*"kind"[^\n]*"company_id"/u,
    );
    expect(sql).toContain("refresh_open_item_charge");
    expect(sql).toContain("refresh_open_credit");
    expect(sql).toMatch(
      /after insert or update of "balance" on [^\n]*ledger_balances/u,
    );
  });

  it("stores future-dated invoices and filters them on read", () => {
    const refresh = between('"refresh_open_item_of"(invoice uuid)', "$$;");

    expect(refresh).not.toContain("current_date");
    expect(refresh).toContain("is not null");

    const page = between('"open_items_page"(', "$$;");

    expect(page).toContain("<= current_date");
  });

  it("pages the stored table and caps the total", () => {
    const body = between('"open_items_page"', '"open_items_for_party"');

    expect(body).toContain("limit least(");
    expect(body).toContain("offset greatest(");
    expect(body).toContain(
      "least(v_total, coalesce(open_items_page.count_cap, 10000))",
    );
    expect(body).not.toContain("effective_at");
  });

  it("rebuilds the same today balance the replay uses", () => {
    const rebuild = between('"rebuild_open_items_of"', "$$;");

    expect(rebuild).toContain("paid_total");
    expect(rebuild).toContain("credited_total");
    expect(rebuild).toContain("ledger_balances");
  });

  it("reports drift against the fold over ledger entries", () => {
    const drift = between('"open_items_drift_rows"', "$$;");

    expect(drift).toContain("full join");
    expect(drift).toContain("ledger_entries");
    expect(sql).toContain('"open_items_drift"(tenant uuid)');
  });

  it("grants each function once: rebuild to the service role only", () => {
    const grants = (name: string): string[] =>
      [
        ...sql.matchAll(
          new RegExp(
            String.raw`grant execute on function "better_supabase"\."${name}"\([^)]*\) to ([^;]+);`,
            "g",
          ),
        ),
      ].map((match) => match[1]!);

    expect(grants("rebuild_open_items")).toEqual(["service_role"]);
    expect(grants("open_items_drift")).toEqual(["authenticated, service_role"]);
    expect(grants("open_items_page")).toEqual(["authenticated, service_role"]);
  });
});
