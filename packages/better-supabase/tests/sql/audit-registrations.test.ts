import { describe, expect, it } from "vitest";

import { auditRegistrations, renderModules } from "../../src/sql/index.ts";

const file = (text: string) => ({ text });

describe("auditRegistrations", () => {
  it("reads named and positional lists, quoted names and arrays", () => {
    expect(
      auditRegistrations([
        file(`
select better_supabase.audit('public.customers', ignore => '{updated_at}', redact => '{kvk}');
select better_supabase.audit('notes', '{updated_at,"Body"}'::text[]);
select better_supabase.audit('crm."Deals"', redact := array['secret']::text[], category => 'sales');
`),
      ]),
    ).toEqual([
      { target: "crm.Deals", ignore: [], redact: ["secret"] },
      { target: "public.customers", ignore: ["updated_at"], redact: ["kvk"] },
      { target: "public.notes", ignore: ["updated_at", "Body"], redact: [] },
    ]);
  });

  it("lets a later call replace an earlier one and unaudit remove it", () => {
    expect(
      auditRegistrations([
        file(
          "select better_supabase.audit('public.a');\nselect better_supabase.audit('public.b');",
        ),
        file(
          "select better_supabase.audit('public.a', ignore => '{x}');\nselect better_supabase.unaudit('public.b');",
        ),
      ]),
    ).toEqual([{ target: "public.a", ignore: ["x"], redact: [] }]);
  });

  it("skips comments, the module's own definitions and non-literal arguments", () => {
    expect(
      auditRegistrations([
        file(`
-- select better_supabase.audit('public.commented');
/* select better_supabase.audit('public.block'); */
create or replace function better_supabase.audit(target regclass, ignore text[] default '{}')
returns void language sql as $$ select 1 $$;
revoke execute on function better_supabase.unaudit(regclass) from public;
select better_supabase.audit(format('%I.%I', 'public', 't'));
select better_supabase.audit('public.dynamic', ignore => columns_of('x'));
select better_supabase.audit('public.unclosed'
`),
      ]),
    ).toEqual([]);
  });
});

describe("audit pgTAP files", () => {
  const audited = [
    { target: "public.customers", ignore: ["updated_at"], redact: ["kvk"] },
    { target: "crm.Deals", ignore: [], redact: [] },
  ];

  it("writes one test file per audited table", () => {
    const tests = renderModules(["audit"], { auditedTables: audited }).filter(
      (entry) => entry.kind === "test",
    );
    expect(tests.map((entry) => entry.path)).toEqual([
      "supabase/tests/900_better_supabase_audit_public_customers.test.sql",
      "supabase/tests/900_better_supabase_audit_crm_deals.test.sql",
    ]);
    const [customers, deals] = tests.map((entry) => entry.contents);
    expect(customers).toContain("-- @bs-module-test audit");
    expect(customers).toContain("select extensions.plan(7);");
    expect(customers).toContain(`like "public"."customers" including defaults`);
    expect(customers).toContain(
      `ignore => '{"updated_at"}'::text[], redact => '{"kvk"}'::text[]`,
    );
    expect(customers).toContain("leave out updated_at");
    expect(customers).toContain("mask kvk");
    expect(deals).toContain("select extensions.plan(5);");
    expect(deals).toContain(`'"crm"."Deals"'::regclass`);
  });

  it("reads the snapshots from the restricted table and skips what an adopted log lacks", () => {
    const restricted = renderModules(["audit"], {
      auditedTables: audited.slice(0, 1),
      modules: { audit: { options: { restricted: true } } },
    }).find((entry) => entry.kind === "test");
    expect(restricted!.contents).toContain(
      'left join "better_supabase"."audit_events_restricted" r on r."entry_id" = l."id"',
    );
    const bare = renderModules(["audit"], {
      auditedTables: audited.slice(0, 1),
      modules: {
        audit: {
          mode: "adopt",
          tables: { log: "public.audit_log" },
          columns: { log: { table: null } },
        },
      },
    }).find((entry) => entry.kind === "test");
    expect(bare!.contents).toContain("select extensions.plan(4);");
    expect(bare!.contents).not.toContain("bs_audit_probe");
  });

  it("writes no test files without audited tables", () => {
    expect(
      renderModules(["audit"]).filter((entry) => entry.kind === "test"),
    ).toEqual([]);
  });
});
