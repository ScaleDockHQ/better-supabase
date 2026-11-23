import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/index.ts";

describe("audit pgTAP files", () => {
  const audited = [
    { target: "public.customers", ignore: ["updated_at"], redact: ["kvk"] },
    { target: "crm.Deals", ignore: [], redact: [] },
  ];

  it("writes one test file for all audited tables", () => {
    const tests = renderBlocks(["audit"], { auditedTables: audited }).filter(
      (entry) => entry.kind === "test",
    );

    expect(tests.map((entry) => entry.path)).toEqual([
      "supabase/tests/900_better_supabase_audit_tables.test.sql",
    ]);
    const customers = tests[0]!.contents;
    const deals = customers;
    expect(customers).toContain("-- @bsb-block-test audit");
    expect(customers).toContain("select extensions.plan(12);");
    expect(customers).toContain(`like "public"."customers" including defaults`);
    expect(customers).toContain(
      `ignore => '{"updated_at"}'::text[], redact => '{"kvk"}'::text[]`,
    );
    expect(customers).toContain("leave out updated_at");
    expect(customers).toContain("mask kvk");
    expect(deals).toContain(`'"crm"."Deals"'::regclass`);
  });

  it("reads the snapshots from the restricted table and skips what the app's log lacks", () => {
    const restricted = renderBlocks(["audit"], {
      auditedTables: audited.slice(0, 1),
      modules: { audit: { options: { restricted: true } } },
    }).find((entry) => entry.kind === "test");

    expect(restricted!.contents).toContain(
      'left join "better_supabase"."audit_events_restricted" r on r."entry_id" = l."id"',
    );

    const bare = renderBlocks(["audit"], {
      auditedTables: audited.slice(0, 1),
      modules: {
        audit: {
          tables: { log: "public.audit_log" },
          columns: { log: { table: null } },
        },
      },
      ownTables: { "public.audit_log": "supabase/schemas/audit.sql" },
    }).find((entry) => entry.kind === "test");

    expect(bare!.contents).toContain("select extensions.plan(4);");
    expect(bare!.contents).not.toContain("bsb_audit_probe");
  });

  it("writes no test files without audited tables", () => {
    expect(
      renderBlocks(["audit"]).filter((entry) => entry.kind === "test"),
    ).toEqual([]);
  });
});
