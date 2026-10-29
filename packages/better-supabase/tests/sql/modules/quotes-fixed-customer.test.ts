import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const OTHER = "99999999-9999-4999-8999-999999999999";
const CUSTOMER = "22222222-2222-4222-8222-222222222222";
const FOREIGN = "44444444-4444-4444-8444-444444444444";
const PRODUCT = "55555555-5555-4555-8555-555555555555";
const MEMBER = "33333333-3333-4333-8333-333333333333";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

const PGCRYPTO = `
create schema if not exists extensions;
create or replace function extensions.gen_random_bytes(n integer) returns bytea
language sql volatile as $$
  select decode(substr(repeat(md5(random()::text), 8), 1, n * 2), 'hex')
$$;
create or replace function extensions.digest(data text, kind text) returns bytea
language sql immutable as $$
  select sha256(convert_to(data, 'UTF8'))
$$;
`;

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);
  perform set_config('request.jwt.claim.sub', '', true);`;

const MEMBER_CALL = `perform set_config('request.jwt.claims', '{"sub":"${MEMBER}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${MEMBER}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);`;

// The app's quotes keep a customer foreign key, no list or discount totals,
// and lines whose product is a uuid foreign key without a type column.
const APP = `
create table public.customers (id uuid primary key, org_id uuid not null);
create table public.products (id uuid primary key);
create table public.quotes (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  number bigint not null,
  identifier text not null,
  revision integer not null default 1,
  title text not null,
  customer_id uuid references public.customers (id),
  owner_user_id uuid,
  currency text not null,
  status text not null default 'draft',
  valid_until date,
  token_hash text unique,
  sent_at timestamptz,
  decided_at timestamptz,
  decided_by text,
  unpublished_changes boolean not null default false,
  subtotal bigint not null default 0,
  tax_total bigint not null default 0,
  total bigint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.quote_lines (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  quote_id uuid not null references public.quotes (id) on delete cascade,
  product_id uuid references public.products (id),
  description text not null,
  quantity numeric(18, 4) not null,
  unit_amount bigint not null,
  tax_rate_bps integer not null default 0,
  position integer not null
);
create function public.recount_quote() returns trigger language plpgsql as $f$
declare
  v_quote uuid := coalesce(new.quote_id, old.quote_id);
begin
  update public.quotes q set
    subtotal = coalesce((select sum(round(l.quantity * l.unit_amount)) from public.quote_lines l where l.quote_id = v_quote), 0),
    tax_total = coalesce((select sum(round(round(l.quantity * l.unit_amount) * l.tax_rate_bps / 10000.0)) from public.quote_lines l where l.quote_id = v_quote), 0)
  where q.id = v_quote;
  update public.quotes q set total = q.subtotal + q.tax_total where q.id = v_quote;
  return null;
end;
$f$;
create trigger quote_lines_recount after insert or update or delete on public.quote_lines
  for each row execute function public.recount_quote();
`;

const DATA = `insert into public.customers values ('${CUSTOMER}', '${TENANT}'), ('${FOREIGN}', '${OTHER}');
insert into public.products values ('${PRODUCT}');`;

const QUOTES: AnyBlocksConfig = {
  quotes: {
    tables: {
      quotes: "public.quotes",
      lines: "public.quote_lines",
      taxLines: null,
    },
    columns: {
      quotes: {
        tenant: "org_id",
        companyType: null,
        companyId: "customer_id",
        contactType: null,
        contactId: null,
        terms: null,
        note: null,
        originType: null,
        originId: null,
        viewedAt: null,
        decisionNote: null,
        decidedUser: null,
        decidedIp: null,
        decidedUserAgent: null,
        pricesIncludeTax: null,
        discountBps: null,
        discountAmount: null,
        depositBps: null,
        depositAmount: null,
        depositRequired: null,
        depositDue: null,
        createdBy: null,
        listTotal: null,
        discountTotal: null,
      },
      lines: {
        tenant: "org_id",
        parent: "quote_id",
        productType: null,
        discountBps: null,
        taxCode: null,
        createdAt: null,
        section: null,
        optional: null,
        selected: null,
        periods: null,
      },
    },
    options: { company: "customer", totals: "app", workingCopy: true },
  },
  invoices: {
    columns: { invoices: { companyType: null } },
    options: { company: "customer" },
  },
};

const SUBJECTS = {
  customer: { table: "public.customers", idType: "uuid", tenant: "org_id" },
} as const;

const OWN = { "public.quotes": "app.sql", "public.quote_lines": "app.sql" };

const BOOT = { timeout: 60_000 };

async function run(check: string, setup = ""): Promise<void> {
  const files = renderBlocks(["quotes", "invoices"], {
    modules: QUOTES,
    subjects: SUBJECTS,
    ownTables: OWN,
  });

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      PGCRYPTO,
      APP,
      ...files
        .filter((file) => file.kind !== "data")
        .map((file) => file.contents),
    ],
    seed: [
      ...files
        .filter((file) => file.kind === "data")
        .map((file) => file.contents),
      DATA,
      setup,
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

const created = `v_id := (better_supabase.create_quote('${TENANT}', jsonb_build_object('title', 'Repair', 'currency', 'EUR',
    'company', jsonb_build_object('id', '${CUSTOMER}')),
    '[{"description": "Part", "quantity": 1, "unitAmount": "10000", "taxRateBps": 2100, "product": {"id": "${PRODUCT}"}},
      {"description": "Labour", "quantity": 2, "unitAmount": "5000"}]'::jsonb) ->> 'id')::uuid;`;

describe("quotes with a fixed customer column", BOOT, () => {
  it("creates, updates and invoices a quote for the customer", async () => {
    await expect(
      run(`do $$
declare
  v_id uuid;
  v_quote jsonb;
  v_invoice jsonb;
begin
  ${SERVICE}
  ${created}
  v_quote := better_supabase.update_quote(v_id, jsonb_build_object('company', jsonb_build_object('type', 'customer', 'id', '${CUSTOMER}')));
  if (select customer_id from public.quotes where id = v_id) <> '${CUSTOMER}'
    or v_quote ->> 'company_type' <> 'customer' then
    raise exception 'customer %', v_quote;
  end if;
  if v_quote ->> 'list_total' <> '20000' or v_quote ->> 'discount_total' <> '0' or v_quote ->> 'total' <> '22100' then
    raise exception 'totals %', v_quote;
  end if;
  if (select product_id from public.quote_lines where quote_id = v_id and position = 1) <> '${PRODUCT}' then
    raise exception 'product %', (select jsonb_agg(l) from public.quote_lines l);
  end if;
  perform better_supabase.send_quote(v_id);
  perform better_supabase.set_quote_lines(v_id, '[{"description": "Other", "quantity": 1, "unitAmount": "100"}]'::jsonb);
  perform better_supabase.decide_quote(v_id, 'accepted', null, 'Ann');
  if (select string_agg(coalesce(product_id::text, '-'), ',' order by position) from public.quote_lines where quote_id = v_id)
    <> '${PRODUCT},-' then
    raise exception 'restored lines %', (select jsonb_agg(l) from public.quote_lines l);
  end if;
  v_invoice := better_supabase.invoice_from_quote(v_id, null);
  if (select company_id from better_supabase.invoices where id = (v_invoice ->> 'id')::uuid) <> '${CUSTOMER}'
    or v_invoice ->> 'company_type' <> 'customer' then
    raise exception 'invoice %', v_invoice;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("refuses another company type", async () => {
    await expect(
      run(`do $$
begin
  ${SERVICE}
  perform better_supabase.create_quote('${TENANT}', jsonb_build_object('title', 'Repair', 'company', jsonb_build_object('type', 'company', 'id', '${CUSTOMER}')), null);
end;
$$;`),
    ).rejects.toThrow(/takes only a customer as the company/);
  });

  it("refuses a customer of another organization", async () => {
    await expect(
      run(`do $$
begin
  ${SERVICE}
  perform better_supabase.create_quote('${TENANT}', jsonb_build_object('title', 'Repair', 'company', jsonb_build_object('id', '${FOREIGN}')), null);
end;
$$;`),
    ).rejects.toThrow(/the company is unknown or not readable/);
  });

  it("refuses a member without the write key", async () => {
    await expect(
      run(
        `do $$
begin
  ${MEMBER_CALL}
  perform better_supabase.create_quote('${TENANT}', jsonb_build_object('title', 'Repair', 'company', jsonb_build_object('id', '${CUSTOMER}')), null);
end;
$$;`,
        `create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select permission <> 'quotes.write' $$;`,
      ),
    ).rejects.toThrow(/not allowed to change quotes/);
  });
});

describe("quotes with a company type column", () => {
  it("keeps the type and id pair by default", () => {
    const sql = renderBlocks(["quotes"], { modules: {} })
      .filter((file) => file.module === "quotes")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain(
      `check (("company_type" is null) = ("company_id" is null))`,
    );
    expect(sql).toContain(`"title", "company_type", "company_id"`);
    expect(sql).toContain(`"list_total" bigint not null default 0`);
    expect(sql).not.toContain("as_column_type(v_company_id");
  });
});
