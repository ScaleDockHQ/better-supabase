import { describe, expect, it } from "vitest";

import { moduleContext } from "../../src/sql/module-context.ts";
import { SQL_MODULES } from "../../src/sql/registry.ts";
import {
  applyTenantScope,
  TENANT_SCOPE_POLICY,
  tenantScopePolicy,
} from "../../src/sql/tenant-scope.ts";

const TABLE = '"better_supabase"."invoices"';
const MEMBERS = "better_supabase.member_organization_ids()";

const scoped = (sql: string): string =>
  applyTenantScope(sql, moduleContext("invoices"));

const scopePolicy = (sql: string): string =>
  sql.slice(sql.indexOf(`create policy ${TENANT_SCOPE_POLICY}`));

describe("tenantScopePolicy", () => {
  it("renders one restrictive policy for every command", () => {
    expect(
      tenantScopePolicy({
        target: TABLE,
        column: '"tenant_id"',
        members: MEMBERS,
      }),
    ).toBe(`drop policy if exists bsb_tenant_scope on ${TABLE};
create policy bsb_tenant_scope on ${TABLE} as restrictive
  for all to authenticated
  using ("tenant_id" in (select ${MEMBERS}))
  with check ("tenant_id" in (select ${MEMBERS}));`);
  });

  it("lets through each distinct grant once, after membership", () => {
    const sql = tenantScopePolicy({
      target: TABLE,
      column: '"tenant_id"',
      members: MEMBERS,
      using: [
        "a = 1",
        " a = 1 ",
        `"tenant_id" in (select ${MEMBERS})`,
        "b = 2",
      ],
    });

    expect(sql).toContain(`using (
    "tenant_id" in (select ${MEMBERS})
    or (a = 1)
    or (b = 2)
  )`);
  });
});

describe("applyTenantScope", () => {
  it("runs on the registered invoices module", () => {
    expect(SQL_MODULES).toHaveProperty("invoices");
  });

  it("scopes a table the block grants to authenticated", () => {
    const sql = scoped(`create policy invoices_read on ${TABLE}
  for select to authenticated
  using (owner = (select auth.uid()));`);

    expect(scopePolicy(sql)).toContain(`using (
    "tenant_id" in (select ${MEMBERS})
    or (owner = (select auth.uid()))
  )
  with check ("tenant_id" in (select ${MEMBERS}));`);
  });

  it("drops the scope policy before the module can drop a function it calls", () => {
    const body = `drop function if exists better_supabase.invoice_readers();
create policy invoices_read on ${TABLE}
  for select to authenticated
  using (true);`;

    const sql = scoped(body);

    const drop = sql.indexOf(
      `drop policy if exists ${TENANT_SCOPE_POLICY} on ${TABLE};
  exception when undefined_table or invalid_schema_name then null;`,
    );

    expect(drop).toBeGreaterThan(-1);
    expect(drop).toBeLessThan(sql.indexOf(body));
  });

  it("checks an update's using when it has no with check", () => {
    const sql = scoped(`create policy invoices_update on ${TABLE}
  for update to authenticated
  using (owner = (select auth.uid()));`);

    expect(scopePolicy(sql)).toContain(`with check (
    "tenant_id" in (select ${MEMBERS})
    or (owner = (select auth.uid()))
  );`);
  });

  it("reads only the top-level using and with check", () => {
    const sql = scoped(`create policy invoices_insert on ${TABLE}
  for insert to authenticated
  with check (exists (select 1 from t where t.note = 'using (x)'));`);

    expect(scopePolicy(sql)).toContain(
      "or (exists (select 1 from t where t.note = 'using (x)'))",
    );
    expect(scopePolicy(sql)).toContain(
      `using ("tenant_id" in (select ${MEMBERS}))`,
    );
  });

  it("scopes a table granted to authenticated without a policy", () => {
    const sql = scoped(`alter table ${TABLE} enable row level security;
grant select on ${TABLE} to authenticated;`);

    expect(scopePolicy(sql))
      .toBe(`create policy bsb_tenant_scope on ${TABLE} as restrictive
  for all to authenticated
  using ("tenant_id" in (select ${MEMBERS}))
  with check ("tenant_id" in (select ${MEMBERS}));
`);
  });

  it("leaves a service-only table alone", () => {
    const sql = `create policy invoices_service on ${TABLE}
  for all to service_role
  using (true);`;

    expect(scoped(sql)).not.toContain(`create policy ${TENANT_SCOPE_POLICY}`);
  });

  it("ignores restrictive and commented-out policies", () => {
    const sql = `create policy invoices_guard on ${TABLE} as restrictive
  for all to authenticated
  using (false);
-- create policy invoices_example on ${TABLE} for select using (true);`;

    expect(scoped(sql)).not.toContain(`create policy ${TENANT_SCOPE_POLICY}`);
  });

  it("adds nothing outside a tenant scope", () => {
    const sql = `create policy tags_read on "better_supabase"."tags"
  for select to authenticated
  using (true);`;

    for (const scope of ["user", "none"] as const) {
      expect(applyTenantScope(sql, moduleContext("tags", { scope }))).toBe(sql);
    }
  });
});
