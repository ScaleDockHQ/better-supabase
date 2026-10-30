import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const CUSTOMER = "22222222-2222-4222-8222-222222222222";
const MEMBER = "33333333-3333-4333-8333-333333333333";
const PRODUCT = "55555555-5555-4555-8555-555555555555";

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

const APP = `
create type public.invoice_pricing as enum ('unit', 'hourly', 'fixed');
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
  create_order_on_accept boolean not null default false,
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
  position numeric not null,
  pricing_mode text not null default 'unit',
  discount_kind text not null default 'none',
  check (pricing_mode <> 'fixed' or quantity = 1)
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

const DATA = `insert into public.customers values ('${CUSTOMER}', '${TENANT}');
insert into public.products values ('${PRODUCT}');`;

const QUOTE_COLUMNS = {
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
};

const LINE_COLUMNS = {
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
};

const BLOCKS: AnyBlocksConfig = {
  quotes: {
    tables: {
      quotes: "public.quotes",
      lines: "public.quote_lines",
      taxLines: null,
    },
    columns: { quotes: QUOTE_COLUMNS, lines: LINE_COLUMNS },
    permissions: {
      decide: "quote.decide",
      accept: "quote.markAccepted",
      reject: "quote.markRejected",
    },
    options: {
      company: "customer",
      totals: "app",
      workingCopy: true,
      extraColumns: { create_order_on_accept: "boolean" },
      lineExtraColumns: { pricing_mode: "text", discount_kind: "text" },
    },
  },
  invoices: {
    columns: { invoices: { companyType: null }, lines: { productType: null } },
    options: {
      company: "customer",
      lineExtraColumns: {
        pricing_mode: "public.invoice_pricing not null default 'unit'",
        line_type: "text",
      },
      depositLine: {
        description: "Aanbetaling {identifier}",
        fields: { line_type: "deposit" },
      },
      quoteLineValues: { pricing_mode: { subscription: "hourly" } },
    },
  },
};

const SUBJECTS = {
  customer: { table: "public.customers", idType: "uuid", tenant: "org_id" },
} as const;

const OWN = { "public.quotes": "app.sql", "public.quote_lines": "app.sql" };

const BOOT = { timeout: 60_000 };

async function run(check: string, setup = ""): Promise<void> {
  const files = renderBlocks(["quotes", "invoices"], {
    modules: BLOCKS,
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

const fixed = `{"description": "Callout", "quantity": 1, "unitAmount": "9000", "taxRateBps": 2100, "fields": {"pricing_mode": "fixed"}}`;
const hours = `{"description": "Hours", "quantity": 3, "unitAmount": "5000", "taxRateBps": 2100, "fields": {"pricing_mode": "hourly"}}`;

const create = (lines: string): string =>
  `(better_supabase.create_quote('${TENANT}', jsonb_build_object('title', 'Repair', 'currency', 'EUR',
    'company', jsonb_build_object('id', '${CUSTOMER}')), '[${lines}]'::jsonb) ->> 'id')::uuid`;

const canWithout = (
  key: string,
): string => `create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select permission <> '${key}' $$;`;

describe(
  "quote lines with checks across the block's and the app's columns",
  BOOT,
  () => {
    it("moves a fixed line, takes the column defaults and restores on acceptance", async () => {
      await expect(
        run(`do $$
declare
  v_id uuid;
begin
  ${SERVICE}
  v_id := ${create(`${fixed}, ${hours}`)};
  if (select create_order_on_accept from public.quotes where id = v_id) is distinct from false then
    raise exception 'a quote column default';
  end if;
  perform better_supabase.set_quote_lines(v_id, '[${hours}]'::jsonb);
  if (select string_agg(pricing_mode || ':' || quantity::integer || ':' || discount_kind, ',' order by position) from public.quote_lines where quote_id = v_id)
    <> 'hourly:3:none' then
    raise exception 'moved %', (select jsonb_agg(l) from public.quote_lines l);
  end if;
  perform better_supabase.set_quote_lines(v_id, '[{"description": "Hours", "quantity": 3, "unitAmount": "5000", "fields": {"pricing_mode": "hourly", "discount_kind": "percent"}}]'::jsonb);
  perform better_supabase.set_quote_lines(v_id, '[{"description": "Hours", "quantity": 2, "unitAmount": "5000", "fields": {"pricing_mode": "hourly"}},
    {"description": "Extra", "quantity": 1, "unitAmount": "100"}]'::jsonb);
  if (select string_agg(pricing_mode || ':' || discount_kind, ',' order by position) from public.quote_lines where quote_id = v_id)
    <> 'hourly:percent,unit:none' then
    raise exception 'kept and defaulted %', (select jsonb_agg(l) from public.quote_lines l);
  end if;
  perform better_supabase.set_quote_lines(v_id, '[${hours}]'::jsonb);
  perform better_supabase.send_quote(v_id);
  perform better_supabase.set_quote_lines(v_id, '[${fixed}]'::jsonb);
  perform better_supabase.decide_quote(v_id, 'accepted', null, 'Ann');
  if (select string_agg(pricing_mode || ':' || quantity::integer, ',' order by position) from public.quote_lines where quote_id = v_id)
    <> 'hourly:3' then
    raise exception 'restored %', (select jsonb_agg(l) from public.quote_lines l);
  end if;
end;
$$;`),
      ).resolves.toBeUndefined();
    });

    it("still refuses a line that breaks the app's check", async () => {
      await expect(
        run(`do $$
begin
  ${SERVICE}
  perform ${create(`{"description": "Callout", "quantity": 2, "unitAmount": "9000", "fields": {"pricing_mode": "fixed"}}`)};
end;
$$;`),
      ).rejects.toThrow(/every line needs a description/);
    });
  },
);

const ANON_CALL = `perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('request.jwt.claim.role', 'anon', true);
  perform set_config('request.jwt.claim.sub', '', true);`;

describe("column defaults stay inside the block's functions", BOOT, () => {
  it("gives a member's new line the column default", async () => {
    await expect(
      run(
        `do $$
declare
  v_id uuid;
begin
  ${MEMBER_CALL}
  set local role authenticated;
  v_id := ${create(`{"description": "Hours", "quantity": 3, "unitAmount": "5000", "fields": {"pricing_mode": "hourly"}}`)};
  reset role;
  if (select string_agg(pricing_mode || ':' || discount_kind, ',') from public.quote_lines where quote_id = v_id) <> 'hourly:none'
    or (select create_order_on_accept from public.quotes where id = v_id) is distinct from false then
    raise exception 'defaults %', (select jsonb_agg(l) from public.quote_lines l);
  end if;
end;
$$;`,
        canWithout("none"),
      ),
    ).resolves.toBeUndefined();
  });

  it.each([
    ["authenticated", MEMBER_CALL],
    ["anon", ANON_CALL],
  ])("refuses %s a direct call", async (role, claims) => {
    await expect(
      run(`do $$
begin
  ${claims}
  set local role ${role};
  perform better_supabase.column_default('public.quote_lines', 'discount_kind', null::text);
end;
$$;`),
    ).rejects.toThrow(/permission denied for function column_default/);
  });

  it("grants it to no API role and wraps it in no API function", () => {
    const sql = renderBlocks(["quotes", "invoices"], {
      modules: {
        ...BLOCKS,
        quotes: { ...BLOCKS["quotes"], api: "api" },
        invoices: { ...BLOCKS["invoices"], api: "api" },
      },
      subjects: SUBJECTS,
      ownTables: OWN,
    })
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain(
      "revoke execute on function better_supabase.column_default(text, text, anyelement) from public, anon, authenticated, service_role;",
    );
    expect(sql).not.toMatch(
      /grant execute on function better_supabase\.column_default/u,
    );
    expect(sql).not.toContain('"api"."column_default"');
    expect(sql).toContain('"api"."set_quote_lines"');
  });
});

describe("quote answers under their own keys", BOOT, () => {
  it("lets a member reject and ask changes without the accept key", async () => {
    await expect(
      run(
        `do $$
declare
  v_one uuid;
  v_two uuid;
begin
  ${SERVICE}
  v_one := ${create(hours)};
  v_two := ${create(hours)};
  perform better_supabase.send_quote(v_one);
  perform better_supabase.send_quote(v_two);
  ${MEMBER_CALL}
  if better_supabase.decide_quote(v_one, 'rejected', 'No', 'Ann') ->> 'status' <> 'rejected'
    or better_supabase.decide_quote(v_two, 'changes_requested', 'Cheaper', 'Ann') ->> 'status' <> 'changes_requested' then
    raise exception 'answers';
  end if;
end;
$$;`,
        canWithout("quote.markAccepted"),
      ),
    ).resolves.toBeUndefined();
  });

  it("refuses an acceptance without the accept key", async () => {
    await expect(
      run(
        `do $$
declare
  v_id uuid;
begin
  ${SERVICE}
  v_id := ${create(hours)};
  perform better_supabase.send_quote(v_id);
  ${MEMBER_CALL}
  perform better_supabase.decide_quote(v_id, 'accepted', null, 'Ann');
end;
$$;`,
        canWithout("quote.markAccepted"),
      ),
    ).rejects.toThrow(/no such quote you can edit/);
  });

  it("falls back to the decide key for changes requested", async () => {
    await expect(
      run(
        `do $$
declare
  v_id uuid;
begin
  ${SERVICE}
  v_id := ${create(hours)};
  perform better_supabase.send_quote(v_id);
  ${MEMBER_CALL}
  perform better_supabase.decide_quote(v_id, 'changes_requested', null, 'Ann');
end;
$$;`,
        canWithout("quote.decide"),
      ),
    ).rejects.toThrow(/no such quote you can edit/);
  });

  it("returns the expired quote to an actor's answer past its date", async () => {
    await expect(
      run(`do $$
declare
  v_id uuid;
  v_quote jsonb;
begin
  ${SERVICE}
  v_id := ${create(hours)};
  perform better_supabase.send_quote(v_id);
  update public.quotes set valid_until = current_date - 1 where id = v_id;
  v_quote := better_supabase.decide_quote(v_id, 'accepted', null, null, null, '{"email": "ann@example.com"}'::jsonb);
  if v_quote ->> 'id' <> v_id::text or v_quote ->> 'status' <> 'expired' or v_quote ->> 'identifier' is null
    or (select status from public.quotes where id = v_id) <> 'expired' then
    raise exception 'expired %', v_quote;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});

const deposit = `v_deposit := better_supabase.create_invoice('${TENANT}', jsonb_build_object('title', 'Deposit', 'currency', 'EUR',
    'company', jsonb_build_object('type', 'customer', 'id', '${CUSTOMER}'), 'depositBps', 2000,
    'origin', jsonb_build_object('type', 'quote', 'id', v_id::text)),
    '[{"description": "Deposit 21", "quantity": 1, "unitAmount": "1000", "taxRateBps": 2100},
      {"description": "Deposit 9", "quantity": 1, "unitAmount": "500", "taxRateBps": 900}]'::jsonb);
  perform better_supabase.issue_invoice((v_deposit ->> 'id')::uuid, current_date);
  select to_jsonb(x) into v_deposit from better_supabase.invoices x where x.id = (v_deposit ->> 'id')::uuid;
  if v_deposit ->> 'identifier' is null then
    raise exception 'no deposit identifier';
  end if;`;

const accepted = `v_id := ${create(`{"description": "Part", "quantity": 1, "unitAmount": "10000", "taxRateBps": 2100, "product": {"id": "${PRODUCT}"}, "fields": {"pricing_mode": "fixed"}},
      {"description": "Plan", "quantity": 2, "unitAmount": "2500", "taxRateBps": 900, "fields": {"pricing_mode": "subscription"}},
      {"description": "Other", "quantity": 1, "unitAmount": "100", "fields": {"pricing_mode": "weird"}}`)};
  perform better_supabase.send_quote(v_id);
  perform better_supabase.decide_quote(v_id, 'accepted', null, 'Ann');`;

describe("invoices from quotes with the app's lines", BOOT, () => {
  it("keeps the product, maps the pricing modes and deducts deposits per rate", async () => {
    await expect(
      run(`do $$
declare
  v_id uuid;
  v_deposit jsonb;
  v_invoice uuid;
begin
  ${SERVICE}
  ${accepted}
  ${deposit}
  v_invoice := (better_supabase.invoice_from_quote(v_id, null) ->> 'id')::uuid;
  if (select string_agg(coalesce(product_id::text, '-') || ':' || pricing_mode::text || ':' || coalesce(line_type, '-'), ',' order by position)
      from better_supabase.invoice_lines where parent_id = v_invoice)
    <> '${PRODUCT}:fixed:-,-:hourly:-,-:unit:-,-:unit:deposit,-:unit:deposit' then
    raise exception 'lines %', (select jsonb_agg(l order by position) from better_supabase.invoice_lines l where parent_id = v_invoice);
  end if;
  if (select string_agg(description || ':' || unit_amount || ':' || tax_rate_bps, ',' order by position)
      from better_supabase.invoice_lines where parent_id = v_invoice and line_type = 'deposit')
    <> 'Aanbetaling ' || (v_deposit ->> 'identifier') || ':-500:900,Aanbetaling ' || (v_deposit ->> 'identifier') || ':-1000:2100' then
    raise exception 'deductions %', (select jsonb_agg(l order by position) from better_supabase.invoice_lines l where parent_id = v_invoice);
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("takes the deduction's description per call", async () => {
    await expect(
      run(`do $$
declare
  v_id uuid;
  v_deposit jsonb;
  v_invoice uuid;
begin
  ${SERVICE}
  ${accepted}
  ${deposit}
  v_invoice := (better_supabase.invoice_from_quote(v_id, null, null, 'Anzahlung {identifier}') ->> 'id')::uuid;
  if (select count(*) from better_supabase.invoice_lines where parent_id = v_invoice and description = 'Anzahlung ' || (v_deposit ->> 'identifier')) <> 2 then
    raise exception 'description %', (select jsonb_agg(l order by position) from better_supabase.invoice_lines l where parent_id = v_invoice);
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("refuses a member without the create key", async () => {
    await expect(
      run(
        `do $$
declare
  v_id uuid;
begin
  ${SERVICE}
  ${accepted}
  ${MEMBER_CALL}
  perform better_supabase.invoice_from_quote(v_id, null);
end;
$$;`,
        canWithout("invoices.write"),
      ),
    ).rejects.toThrow(/no such quote you can invoice/);
  });
});

describe("the defaults", () => {
  const sql = renderBlocks(["quotes", "invoices"], { modules: {} })
    .map((file) => file.contents)
    .join("\n");

  it("keeps one decide key, the deposit description and no deposit fields", () => {
    expect(sql).not.toContain("(case decide_quote.decision");
    expect(sql).toContain("'Deposit {identifier}'");
    expect(sql).not.toContain("'fields', '{");
  });

  it("refuses deposit fields that are no line extra column", () => {
    expect(() =>
      renderBlocks(["quotes", "invoices"], {
        modules: {
          invoices: { options: { depositLine: { fields: { kind: "x" } } } },
        },
      }),
    ).toThrow(/depositLine.fields must be an object of/);
    expect(() =>
      renderBlocks(["quotes", "invoices"], {
        modules: {
          invoices: { options: { quoteLineValues: { kind: { a: 1 } } } },
        },
      }),
    ).toThrow(/quoteLineValues must map column names/);
  });
});
