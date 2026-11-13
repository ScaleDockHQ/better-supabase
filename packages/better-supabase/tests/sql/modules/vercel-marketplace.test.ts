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
      expect(sql).toContain(`create table "better_supabase"."${table}"`);
    }
  });

  it("guards invoices by event time so an older event never wins", () => {
    expect(body()).toMatch(/where [^\n]*"event_at" <= excluded\."event_at"/);
  });

  it("grants every function but the two tenant reads to the service role only", () => {
    const sql = body();

    expect(sql).toContain(
      `grant execute on function ${fn("record_marketplace_invoice")}(text, text, text, timestamptz, timestamptz, numeric, text, jsonb, timestamptz) to service_role;`,
    );

    expect(
      sql.match(/grant execute on function [^;]*to [^;]*authenticated[^;]*;/g),
    ).toEqual([
      `grant execute on function ${fn("marketplace_installation_for")}(text) to authenticated, service_role;`,
      `grant execute on function ${fn("marketplace_resources_for")}(text) to authenticated, service_role;`,
    ]);
  });

  it("answers the tenant reads for members and leaves out secret handles", () => {
    const sql = body();

    expect(sql).toContain(
      "where m.id::text = marketplace_installation_for.tenant",
    );
    expect(sql).toContain("- 'access_token_secret_id'");
    expect(sql).toContain("- 'secret_refs'");
  });

  it("backfills reported_quantity for rows reported before version 2", () => {
    const [plan] = upgradePlan([{ module: "vercel-marketplace", version: 1 }]);
    expect(plan).toMatchObject({ from: 1, to: 3 });
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
