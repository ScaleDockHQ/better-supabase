import { describe, expect, it } from "vitest";

import { moduleBody } from "../../../src/sql/render.ts";
import { upgradePlan } from "../../../src/sql/upgrade.ts";

const body = () => moduleBody("vercel-marketplace", { modules: {} })!;
const fn = (name: string) => `"better_supabase"."${name}"`;

describe("vercel-marketplace module", () => {
  it("keeps installations, resources, plans, invoices and meter reports", () => {
    const sql = body();

    for (const table of [
      "marketplace_installations",
      "marketplace_resources",
      "marketplace_plans",
      "marketplace_invoices",
      "marketplace_meter_reports",
    ]) {
      expect(sql).toContain(
        `create table if not exists "better_supabase"."${table}"`,
      );
    }
  });

  it("guards invoices by event time so an older event never wins", () => {
    expect(body()).toMatch(/where [^\n]*"event_at" <= excluded\."event_at"/);
  });

  it("grants every function to the service role only", () => {
    const sql = body();

    expect(sql).toContain(
      `grant execute on function ${fn("record_marketplace_invoice")}(text, text, text, timestamptz, timestamptz, numeric, text, jsonb, timestamptz) to service_role;`,
    );
    expect(sql).not.toMatch(/grant execute[^;]*to [^;]*authenticated/);
  });

  it("backfills reported_quantity for rows reported before version 2", () => {
    const [plan] = upgradePlan([{ module: "vercel-marketplace", version: 1 }]);
    expect(plan).toMatchObject({ from: 1, to: 2 });
    const sql = plan!.steps[0]!.sql;
    const table = `"better_supabase"."marketplace_meter_reports"`;

    expect(sql).toContain(
      `alter table ${table} add column if not exists "reported_quantity" numeric not null default 0;`,
    );
    expect(sql).toContain(
      `update ${table} set "reported_quantity" = "quantity" where "reported_at" is not null;`,
    );
  });
});
