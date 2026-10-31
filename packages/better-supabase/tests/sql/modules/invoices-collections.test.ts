import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const sqlOf = (names: readonly string[], module = "invoices"): string =>
  renderBlocks([...names])
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

describe("invoice collections", () => {
  it("adds party payments, party credit and the dunning functions", () => {
    const sql = sqlOf(["invoices", "outbox"]);

    expect(sql).toContain('"better_supabase"."invoice_dunning_levels"');
    expect(sql).toContain('"dunning_level" integer not null default 0');
    expect(sql).toContain('"better_supabase"."record_party_payment"(');
    expect(sql).toContain('"better_supabase"."apply_party_credit"(');
    expect(sql).toContain('"better_supabase"."list_party_credits"(');
    expect(sql).toContain('"better_supabase"."run_invoice_dunning"(');
    expect(sql).toContain('"better_supabase"."pause_invoice_dunning"(');
    expect(sql).toContain("'invoices:credit:' ||");
    expect(sql).toContain("'invoice.dunning_escalated'");
    expect(sql).toContain("'invoice.dunning_paused'");
    expect(sql).toContain("'invoice.credit_applied'");
    expect(sql).toContain("'invoices.collect'");
  });

  it("runs dunning as the service role only", () => {
    const sql = sqlOf(["invoices"]);

    const grant = sql
      .split("\n")
      .find(
        (line) =>
          line.startsWith("grant execute") &&
          line.includes("run_invoice_dunning"),
      );

    expect(grant).toContain("service_role");
    expect(grant).not.toContain("authenticated");
  });

  it("adds a dunning fee as a charge", () => {
    expect(sqlOf(["invoices"])).toContain("'Reminder fee, level ' || v_level.");
  });

  it("notifies the creator only with notifications installed", () => {
    expect(sqlOf(["invoices", "notifications"])).toContain(
      "' reached reminder level '",
    );
    expect(sqlOf(["invoices"])).not.toContain("' reached reminder level '");
  });

  it("books a party payment's rest with accounting installed", () => {
    const sql = sqlOf(["invoices", "accounting"]);

    expect(sql).toContain("accounting_invoice_party_payment_lines");
    expect(sql).toContain("'Payment on account'");
    expect(sqlOf(["invoices"])).not.toContain(
      "accounting_invoice_party_payment_lines",
    );
  });
});
