import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const payment = (permissions: Readonly<Record<string, string>>): string => {
  const sql = renderBlocks(["invoices"], {
    modules: { invoices: { permissions } },
  })
    .map((file) => file.contents)
    .join("\n");

  const start = sql.indexOf(
    'create or replace function "better_supabase"."record_invoice_payment"',
  );

  return sql.slice(start, sql.indexOf("$$;", start));
};

describe("record_invoice_payment", () => {
  it("checks only the payment key without a settle key", () => {
    const body = payment({ payment: "invoice.record_payment" });

    expect(body).toContain("'invoice.record_payment'");
    expect(body).not.toContain("record_invoice_payment.amount = (");
    expect(body).toContain(") is not true then");
    expect(body.indexOf("for update")).toBeGreaterThan(
      body.indexOf("INVOICE_FORBIDDEN"),
    );
  });

  it("lets the settle key pay the whole balance or replay a recorded payment", () => {
    const body = payment({
      payment: "invoice.record_payment",
      settle: "invoice.mark_paid",
    });

    expect(body).toContain("'invoice.mark_paid'");
    expect(body).toContain("record_invoice_payment.amount = (");
    expect(body).toContain("record_invoice_payment.amount > 0 and");
    expect(body).toContain("INVOICE_FORBIDDEN");
  });
});

const TENANT = "11111111-1111-4111-8111-111111111111";
const READER = "22222222-2222-4222-8222-222222222222";
const STRANGER = "33333333-3333-4333-8333-333333333333";

// No caller holds a key. The reader is a member, and the app's own policy shows
// them every invoice; the stranger is neither.
const SETUP = `
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select false $$;
create or replace function better_supabase.member_organization_ids(roles text[] default null)
returns setof uuid language sql stable as $$ select '${TENANT}'::uuid where auth.uid() = '${READER}'::uuid $$;
grant select on better_supabase.invoices to authenticated;
create policy invoices_reader_sees on better_supabase.invoices for select to authenticated
  using (auth.uid() = '${READER}'::uuid);
`;

const as = (user: string): string =>
  `perform set_config('request.jwt.claims', '{"sub":"${user}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${user}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);`;

describe("an invoice refusal for a caller the read key doesn't cover", () => {
  it(
    "is forbidden when the table's policies show the row and not found otherwise",
    { timeout: 60_000 },
    async () => {
      const files = renderBlocks(["invoices"], {});

      await using stack = await liteStack({
        driver: "pglite",
        migrations: [
          `do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end $$;`,
          ...files
            .filter((file) => file.kind === "schema")
            .map((file) => file.contents),
        ],
        seed: [
          ...files
            .filter((file) => file.kind === "data")
            .map((file) => file.contents),
          SETUP,
          `do $$
declare
  v_invoice uuid;
  v_hint text;
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);
  perform set_config('request.jwt.claim.sub', '', true);
  v_invoice := (better_supabase.create_invoice('${TENANT}', '{"title": "Work", "currency": "EUR"}'::jsonb,
    '[{"description": "Work", "quantity": 1, "unitAmount": "10000"}]'::jsonb) ->> 'id')::uuid;
  ${as(READER)}
  begin
    perform better_supabase.delete_invoice(v_invoice);
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
  end;
  if v_hint is distinct from 'INVOICE_FORBIDDEN' then
    raise exception 'the reader got %', v_hint;
  end if;
  ${as(STRANGER)}
  v_hint := null;
  begin
    perform better_supabase.delete_invoice(v_invoice);
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
  end;
  if v_hint is distinct from 'INVOICE_NOT_FOUND' then
    raise exception 'the stranger got %', v_hint;
  end if;
end;
$$;`,
        ],
      });

      expect(stack.url).not.toBe("");
    },
  );
});
