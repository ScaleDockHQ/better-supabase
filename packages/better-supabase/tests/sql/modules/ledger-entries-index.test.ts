import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";
import { upgradePlan } from "../../../src/sql/upgrade.ts";

describe("ledger entries", () => {
  it("indexes entries by tenant and effective time and reads them by id", () => {
    const text = renderBlocks(["ledger"])
      .map((file) => file.contents)
      .join("\n");

    expect(text).toContain('"effective_at"');
    expect(text).toContain("get_many");
    expect(text).toMatch(/ledger_entries[\s\S]*tenant_id[\s\S]*effective_at/);
  });

  it("copies effective_at from the transaction onto entries posted before the column", () => {
    const plan = upgradePlan([
      { module: "memberships", version: 3 },
      { module: "permissions", version: 1 },
      { module: "ledger", version: 1 },
    ]).find((entry) => entry.module === "ledger");

    const sql = plan?.steps.map((step) => step.sql).join("\n") ?? "";

    expect(sql).toContain(
      'alter table "better_supabase"."ledger_entries" add column if not exists "effective_at" timestamptz not null default now();',
    );
    expect(sql).toMatch(
      /update "better_supabase"\."ledger_entries" e set "effective_at" = t\."effective_at"\s+from "better_supabase"\."ledger_transactions" t\s+where t\."id" = e\."transaction_id"/u,
    );
  });
});
