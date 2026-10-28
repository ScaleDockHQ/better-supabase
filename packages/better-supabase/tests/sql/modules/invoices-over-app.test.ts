import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

// The app's own invoices table: renamed columns, enum status and kind, and
// no company, contact, note, origin, deposit or void reason columns. The
// module adds the totals and dates it is missing.
const APP = `
create type public.bill_state as enum ('draft', 'issued', 'partially_paid', 'paid', 'void', 'uncollectible');
create type public.bill_kind as enum ('invoice', 'credit_note');

create table public.bills (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  kind public.bill_kind not null default 'invoice',
  seq bigint,
  code text,
  original_id uuid references public.bills (id),
  title text not null,
  currency char(3) not null,
  state public.bill_state not null default 'draft',
  terms_days integer not null default 14,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
`;

const OWN_TABLES = { "public.bills": "app.sql" };

const BLOCKS: AnyBlocksConfig = {
  invoices: {
    tables: { invoices: "public.bills" },
    columns: {
      invoices: {
        tenant: "org_id",
        number: "seq",
        identifier: "code",
        status: "state",
        companyType: null,
        companyId: null,
        contactType: null,
        contactId: null,
        voidReason: null,
        note: null,
        originType: null,
        originId: null,
        depositBps: null,
        createdBy: null,
      },
    },
  },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(
  check: string,
  modules: AnyBlocksConfig = BLOCKS,
  app: string = APP,
  ownTables: Readonly<Record<string, string>> = OWN_TABLES,
): Promise<void> {
  const files = renderBlocks(["invoices"], { modules, ownTables });

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      app,
      ...files
        .filter((file) => file.kind !== "data")
        .map((file) => file.contents),
    ],
    seed: [
      ...files
        .filter((file) => file.kind === "data")
        .map((file) => file.contents),
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("invoices over the app's tables", BOOT, () => {
  it("creates, issues, pays, credits and voids in enum columns", async () => {
    await expect(
      run(`do $$
declare
  v_invoice jsonb;
  v_id uuid;
  v_credit jsonb;
  v_other uuid;
begin
  ${SERVICE}
  v_invoice := better_supabase.create_invoice('${TENANT}', '{"title": "Website", "currency": "eur"}'::jsonb,
    '[{"description": "Design", "quantity": 2, "unitAmount": "5000"}]'::jsonb);
  v_id := (v_invoice ->> 'id')::uuid;
  if v_invoice ->> 'status' <> 'draft' or (v_invoice ->> 'total')::bigint <> 10000 then
    raise exception 'created %', v_invoice;
  end if;
  perform better_supabase.issue_invoice(v_id, current_date);
  if (select state from public.bills where id = v_id) <> 'issued' or (select seq from public.bills where id = v_id) is null then
    raise exception 'issue missed';
  end if;
  perform better_supabase.record_invoice_payment(v_id, 4000, 'EUR', now(), 'bank', 'tx-1');
  perform better_supabase.record_invoice_payment(v_id, 4000, 'EUR', now(), 'bank', 'tx-1');
  if (select state from public.bills where id = v_id) <> 'partially_paid' then
    raise exception 'partial payment left %', (select state from public.bills where id = v_id);
  end if;
  if jsonb_typeof(better_supabase.invoice_aging('${TENANT}', 'EUR', current_date)) is null then
    raise exception 'invoice_aging returned nothing';
  end if;
  v_credit := better_supabase.credit_invoice(v_id, '[{"description": "Discount", "quantity": 1, "unitAmount": "6000"}]'::jsonb, null);
  perform better_supabase.issue_invoice((v_credit ->> 'id')::uuid, current_date);
  if (select kind from public.bills where id = (v_credit ->> 'id')::uuid) <> 'credit_note'
    or (select state from public.bills where id = v_id) <> 'paid' then
    raise exception 'the credit note left %', (select state from public.bills where id = v_id);
  end if;
  v_other := (better_supabase.create_invoice('${TENANT}', '{"title": "Hosting", "currency": "EUR"}'::jsonb,
    '[{"description": "Month", "quantity": 1, "unitAmount": "900"}]'::jsonb) ->> 'id')::uuid;
  perform better_supabase.issue_invoice(v_other, current_date);
  perform better_supabase.void_invoice(v_other, 'sent twice');
  if (select state from public.bills where id = v_other) <> 'void' then
    raise exception 'void missed';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("issues with a due date or none, removes charges and writes off with a reason", async () => {
    const app = `${APP.replace("terms_days integer not null default 14,", "terms_days integer,\n  write_off_reason text,")}
create table public.bill_charges (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  bill_id uuid not null references public.bills (id) on delete cascade,
  amount bigint not null,
  created_at timestamptz not null default now()
);
`;

    await expect(
      run(
        `do $$
declare
  v_id uuid;
  v_open uuid;
  v_charge uuid;
  v_invoice jsonb;
begin
  ${SERVICE}
  v_id := (better_supabase.create_invoice('${TENANT}', '{"title": "Website", "currency": "EUR"}'::jsonb,
    '[{"description": "Design", "quantity": 1, "unitAmount": "5000"}]'::jsonb) ->> 'id')::uuid;
  v_invoice := better_supabase.issue_invoice(v_id, '2099-01-10', due_on => '2099-02-28');
  if (select due_on from public.bills where id = v_id) <> '2099-02-28' then
    raise exception 'due %', v_invoice;
  end if;
  v_open := (better_supabase.create_invoice('${TENANT}', '{"title": "Hosting", "currency": "EUR", "termsDays": null}'::jsonb,
    '[{"description": "Month", "quantity": 1, "unitAmount": "900"}]'::jsonb) ->> 'id')::uuid;
  perform better_supabase.issue_invoice(v_open, '2099-01-10');
  if (select terms_days from public.bills where id = v_open) is not null or (select due_on from public.bills where id = v_open) is not null then
    raise exception 'no terms %', (select row_to_json(b) from public.bills b where id = v_open);
  end if;
  perform better_supabase.record_invoice_payment(v_id, 5000, 'EUR', now(), 'bank', 'tx-1');
  perform better_supabase.add_invoice_charge(v_id, 1500, 'EUR', 'Late fee');
  v_charge := (select id from public.bill_charges where bill_id = v_id);
  if (select state from public.bills where id = v_id) <> 'partially_paid' then
    raise exception 'charged %', (select state from public.bills where id = v_id);
  end if;
  v_invoice := better_supabase.remove_invoice_charge(v_charge);
  if (select state from public.bills where id = v_id) <> 'paid' or exists (select 1 from public.bill_charges) then
    raise exception 'removed %', v_invoice;
  end if;
  perform better_supabase.write_off_invoice(v_open, 'customer went bankrupt');
  if (select state from public.bills where id = v_open) <> 'uncollectible'
    or (select write_off_reason from public.bills where id = v_open) <> 'customer went bankrupt' then
    raise exception 'written off %', (select row_to_json(b) from public.bills b where id = v_open);
  end if;
end;
$$;`,
        {
          invoices: {
            ...BLOCKS["invoices"],
            tables: {
              invoices: "public.bills",
              charges: "public.bill_charges",
            },
            columns: {
              ...BLOCKS["invoices"]?.columns,
              invoices: {
                ...BLOCKS["invoices"]?.columns?.["invoices"],
                writeOffReason: "write_off_reason",
              },
              charges: {
                tenant: "org_id",
                invoice: "bill_id",
                currency: null,
                description: null,
                createdBy: null,
              },
            },
          },
        },
        app,
        { ...OWN_TABLES, "public.bill_charges": "app.sql" },
      ),
    ).resolves.toBeUndefined();
  });

  it("credits a paid invoice up to its total, reverses manual payments and numbers only issued invoices", async () => {
    await expect(
      run(`do $$
declare
  v_id uuid;
  v_empty uuid;
  v_credit jsonb;
  v_payment uuid;
  v_invoice jsonb;
begin
  ${SERVICE}
  v_empty := (better_supabase.create_invoice('${TENANT}', '{"title": "Nothing", "currency": "EUR"}'::jsonb, '[]'::jsonb) ->> 'id')::uuid;
  begin
    perform better_supabase.issue_invoice(v_empty, null);
    raise exception 'an empty invoice was issued';
  exception when others then
    if sqlerrm = 'an empty invoice was issued' then
      raise;
    end if;
  end;
  if (select seq from public.bills where id = v_empty) is not null then
    raise exception 'a draft carries a number';
  end if;
  v_id := (better_supabase.create_invoice('${TENANT}', '{"title": "Website", "currency": "EUR"}'::jsonb,
    '[{"description": "Design", "quantity": 1, "unitAmount": "5000"}]'::jsonb) ->> 'id')::uuid;
  v_invoice := better_supabase.issue_invoice(v_id, null);
  if (select seq from public.bills where id = v_id) <> 1 or (select issued_on from public.bills where id = v_id) <> current_date then
    raise exception 'numbered %', v_invoice;
  end if;
  v_invoice := better_supabase.record_invoice_payment(v_id, 5000, 'EUR', now(), 'stripe', 'pi_1');
  begin
    perform better_supabase.reverse_invoice_payment((v_invoice -> 'payments' -> 0 ->> 'id')::uuid, 'wrong');
    raise exception 'a provider payment was reversed';
  exception when others then
    if sqlerrm not like '%provider%' then
      raise;
    end if;
  end;
  v_credit := better_supabase.credit_invoice(v_id, '[{"description": "Refund", "quantity": 1, "unitAmount": "2000"}]'::jsonb, null);
  perform better_supabase.issue_invoice((v_credit ->> 'id')::uuid, null);
  if (select credited_total from public.bills where id = v_id) <> 2000 then
    raise exception 'a paid invoice was not credited';
  end if;
  v_credit := better_supabase.credit_invoice(v_id, '[{"description": "Too much", "quantity": 1, "unitAmount": "3001"}]'::jsonb, null);
  begin
    perform better_supabase.issue_invoice((v_credit ->> 'id')::uuid, null);
    raise exception 'a credit above the total was issued';
  exception when others then
    if sqlerrm = 'a credit above the total was issued' then
      raise;
    end if;
  end;
  perform better_supabase.record_invoice_payment(v_id, -2000, 'EUR', now(), 'bank', 'refund-1');
  v_id := (better_supabase.create_invoice('${TENANT}', '{"title": "Hosting", "currency": "EUR"}'::jsonb,
    '[{"description": "Month", "quantity": 1, "unitAmount": "900"}]'::jsonb) ->> 'id')::uuid;
  perform better_supabase.issue_invoice(v_id, null);
  v_invoice := better_supabase.record_invoice_payment(v_id, 900, 'EUR', now(), 'bank', 'tx-9');
  v_payment := (v_invoice -> 'payments' -> 0 ->> 'id')::uuid;
  v_invoice := better_supabase.reverse_invoice_payment(v_payment, 'bounced');
  if (select state from public.bills where id = v_id) <> 'issued' or (select paid_total from public.bills where id = v_id) <> 0
    or jsonb_array_length(v_invoice -> 'payments') <> 2 then
    raise exception 'reversed %', v_invoice;
  end if;
  begin
    perform better_supabase.reverse_invoice_payment(v_payment, 'again');
    raise exception 'reversed twice';
  exception when others then
    if sqlerrm = 'reversed twice' then
      raise;
    end if;
  end;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("keeps line rates as percentages in the app's line table", async () => {
    await expect(
      run(
        `do $$
declare
  v_invoice jsonb;
  v_id uuid;
begin
  ${SERVICE}
  v_invoice := better_supabase.create_invoice('${TENANT}', '{"title": "Repair", "currency": "EUR"}'::jsonb,
    '[{"description": "Part", "quantity": 1, "unitAmount": "10000", "taxRateBps": 2100, "discountBps": 1050}]'::jsonb);
  v_id := (v_invoice ->> 'id')::uuid;
  if (select vat_rate from public.bill_lines where bill_id = v_id) <> 21.00
    or (select discount_rate from public.bill_lines where bill_id = v_id) <> 10.50 then
    raise exception 'stored %', (select row_to_json(l) from public.bill_lines l where bill_id = v_id);
  end if;
  if (v_invoice -> 'lines' -> 0 ->> 'taxRateBps')::integer <> 2100
    or (v_invoice -> 'lines' -> 0 ->> 'discountBps')::integer <> 1050
    or (v_invoice ->> 'total')::bigint <> 10830 then
    raise exception 'read %', v_invoice;
  end if;
end;
$$;`,
        {
          invoices: {
            ...BLOCKS["invoices"],
            tables: { invoices: "public.bills", lines: "public.bill_lines" },
            columns: {
              ...BLOCKS["invoices"]?.columns,
              lines: {
                tenant: "org_id",
                parent: "bill_id",
                taxRateBps: "vat_rate",
                discountBps: "discount_rate",
                productType: null,
                productId: null,
                taxCode: null,
                createdAt: null,
              },
            },
            options: { lineRates: "percent" },
          },
        },
        `${APP}
create table public.bill_lines (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  bill_id uuid not null references public.bills (id) on delete cascade,
  description text not null,
  quantity numeric not null default 1,
  unit_amount bigint not null,
  vat_rate numeric(5, 2) not null default 0,
  discount_rate numeric(5, 2) not null default 0,
  position integer not null default 0
);
`,
        { ...OWN_TABLES, "public.bill_lines": "app.sql" },
      ),
    ).resolves.toBeUndefined();
    expect(() =>
      renderBlocks(["invoices"], {
        modules: { invoices: { options: { lineRates: "percent" } } },
      }),
    ).toThrow(/lineRates/);
  });

  it("refuses a note the app's table has no column for", async () => {
    await expect(
      run(`do $$
begin
  ${SERVICE}
  perform better_supabase.create_invoice('${TENANT}', '{"title": "Website", "currency": "EUR", "note": "thanks"}'::jsonb, null);
end;
$$;`),
    ).rejects.toThrow(/no note column/);
  });

  it("writes and reads statuses through a value map", async () => {
    await expect(
      run(
        `do $$
declare
  v_invoice jsonb;
  v_id uuid;
  v_other uuid;
begin
  ${SERVICE}
  v_id := (better_supabase.create_invoice('${TENANT}', '{"title": "Website", "currency": "EUR"}'::jsonb,
    '[{"description": "Design", "quantity": 1, "unitAmount": "10000"}]'::jsonb) ->> 'id')::uuid;
  v_invoice := better_supabase.issue_invoice(v_id, current_date);
  if (select state::text from public.bills where id = v_id) <> 'sent' or v_invoice ->> 'status' <> 'issued' then
    raise exception 'issued %', v_invoice;
  end if;
  update public.bills set state = 'overdue' where id = v_id;
  v_invoice := better_supabase.record_invoice_payment(v_id, 4000, 'EUR', now(), 'bank', 'tx-1');
  if (select state::text from public.bills where id = v_id) <> 'sent' then
    raise exception 'partial %', v_invoice;
  end if;
  if (better_supabase.invoice_aging('${TENANT}', 'EUR', current_date) ->> 'outstanding')::bigint <> 6000 then
    raise exception 'aging %', better_supabase.invoice_aging('${TENANT}', 'EUR', current_date);
  end if;
  perform better_supabase.record_invoice_payment(v_id, 6000, 'EUR', now(), 'bank', 'tx-2');
  if (select state::text from public.bills where id = v_id) <> 'paid' then
    raise exception 'paid missed';
  end if;
  v_other := (better_supabase.create_invoice('${TENANT}', '{"title": "Hosting", "currency": "EUR"}'::jsonb,
    '[{"description": "Month", "quantity": 1, "unitAmount": "900"}]'::jsonb) ->> 'id')::uuid;
  perform better_supabase.issue_invoice(v_other, current_date);
  v_invoice := better_supabase.void_invoice(v_other, 'sent twice');
  if (select state::text from public.bills where id = v_other) <> 'canceled' or v_invoice ->> 'status' <> 'void' then
    raise exception 'void %', v_invoice;
  end if;
end;
$$;`,
        {
          invoices: {
            ...BLOCKS["invoices"],
            values: {
              invoices: {
                status: {
                  issued: ["sent", "overdue"],
                  partially_paid: ["sent"],
                  void: "canceled",
                },
              },
            },
          },
        },
        APP.replace(
          "('draft', 'issued', 'partially_paid', 'paid', 'void', 'uncollectible')",
          "('draft', 'sent', 'overdue', 'paid', 'canceled', 'uncollectible')",
        ),
      ),
    ).resolves.toBeUndefined();
  });

  it("keeps the app's totals, a customer and contact foreign key, a quote origin, charges and numbering by issue date", async () => {
    const app = `
create table public.customers (id uuid primary key, org_id uuid not null);
create table public.customer_contacts (id uuid primary key, org_id uuid not null);
create table public.quotes (id uuid primary key, org_id uuid not null);
create type public.invoice_state as enum ('draft', 'sent', 'overdue', 'paid', 'canceled', 'uncollectible');
create table public.invoices (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  kind text not null default 'invoice',
  number bigint,
  formatted_number text,
  original_invoice_id uuid references public.invoices (id),
  title text not null,
  customer_id uuid not null references public.customers (id) on delete restrict,
  customer_contact_id uuid references public.customer_contacts (id) on delete set null,
  source_quote_id uuid references public.quotes (id) on delete set null,
  currency text not null default 'EUR',
  status public.invoice_state not null default 'draft',
  due_days integer not null default 14,
  issued_on date,
  due_on date,
  subtotal_excl_cents bigint not null default 0,
  vat_total_cents bigint not null default 0,
  total_incl_cents bigint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.invoice_lines (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  invoice_id uuid not null references public.invoices (id) on delete cascade,
  title text not null,
  quantity numeric(14, 4) not null default 1,
  unit_price_cents bigint not null default 0,
  vat_bps integer not null default 0,
  position integer not null default 0
);
create table public.invoice_charges (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  invoice_id uuid not null references public.invoices (id) on delete cascade,
  amount_cents bigint not null check (amount_cents > 0),
  reason text,
  kind text not null check (kind in ('collection', 'interest')),
  created_at timestamptz not null default now()
);
-- The app's own totals: VAT per rate on the summed lines, rounded once.
create function public.recompute_invoice_totals() returns trigger language plpgsql as $f$
declare
  v_invoice uuid := coalesce(new.invoice_id, old.invoice_id);
begin
  update public.invoices i set
    subtotal_excl_cents = coalesce((select sum(round(l.quantity * l.unit_price_cents)) from public.invoice_lines l where l.invoice_id = v_invoice), 0),
    vat_total_cents = coalesce((select sum(round(s.net * s.vat_bps / 10000.0)) from (
      select l.vat_bps, sum(l.quantity * l.unit_price_cents) as net from public.invoice_lines l where l.invoice_id = v_invoice group by l.vat_bps) s), 0),
    total_incl_cents = 0
  where i.id = v_invoice;
  update public.invoices i set total_incl_cents = i.subtotal_excl_cents + i.vat_total_cents where i.id = v_invoice;
  return null;
end;
$f$;
create trigger invoice_lines_totals after insert or update or delete on public.invoice_lines
  for each row execute function public.recompute_invoice_totals();
`;

    const modules: AnyBlocksConfig = {
      invoices: {
        tables: {
          invoices: "public.invoices",
          lines: "public.invoice_lines",
          charges: "public.invoice_charges",
        },
        columns: {
          invoices: {
            tenant: "org_id",
            identifier: "formatted_number",
            original: "original_invoice_id",
            termsDays: "due_days",
            subtotal: "subtotal_excl_cents",
            taxTotal: "vat_total_cents",
            total: "total_incl_cents",
            listTotal: null,
            discountTotal: null,
            companyType: null,
            companyId: "customer_id",
            contactType: null,
            contactId: "customer_contact_id",
            originType: null,
            originId: "source_quote_id",
            voidReason: null,
            note: null,
            depositBps: null,
            createdBy: null,
          },
          lines: {
            tenant: "org_id",
            parent: "invoice_id",
            description: "title",
            unitAmount: "unit_price_cents",
            taxRateBps: "vat_bps",
            productType: null,
            productId: null,
            discountBps: null,
            taxCode: null,
            createdAt: null,
          },
          charges: {
            tenant: "org_id",
            invoice: "invoice_id",
            amount: "amount_cents",
            description: "reason",
            createdBy: null,
            currency: null,
          },
        },
        values: {
          invoices: {
            status: {
              issued: ["sent", "overdue"],
              partially_paid: ["sent"],
              void: "canceled",
            },
          },
        },
        options: {
          company: "customer",
          contact: "customer_contact",
          totals: "app",
          chargeExtraColumns: { kind: "text not null" },
        },
      },
      numbering: {
        options: {
          entities: { invoice: { period: "year", format: "{yyyy}-{n}" } },
        },
      },
    };

    const files = renderBlocks(["invoices", "numbering"], {
      modules,
      subjects: {
        customer: {
          table: "public.customers",
          idType: "uuid",
          tenant: "org_id",
        },
        customer_contact: {
          table: "public.customer_contacts",
          idType: "uuid",
          tenant: "org_id",
        },
      },
      ownTables: {
        "public.invoices": "app.sql",
        "public.invoice_lines": "app.sql",
        "public.invoice_charges": "app.sql",
      },
    });

    const check = `insert into public.customers values ('22222222-2222-4222-8222-222222222222', '${TENANT}');
insert into public.customer_contacts values ('33333333-3333-4333-8333-333333333333', '${TENANT}');
insert into public.quotes values ('44444444-4444-4444-8444-444444444444', '${TENANT}');
do $$
declare
  v_invoice jsonb;
  v_id uuid;
begin
  ${SERVICE}
  v_invoice := better_supabase.create_invoice('${TENANT}', jsonb_build_object(
    'title', 'Repair', 'currency', 'EUR',
    'company', jsonb_build_object('type', 'customer', 'id', '22222222-2222-4222-8222-222222222222'),
    'contact', jsonb_build_object('id', '33333333-3333-4333-8333-333333333333'),
    'origin', jsonb_build_object('type', 'quote', 'id', '44444444-4444-4444-8444-444444444444')),
    '[{"description": "Part", "quantity": 1, "unitAmount": "1003", "taxRateBps": 2100},
      {"description": "Part", "quantity": 1, "unitAmount": "1003", "taxRateBps": 2100}]'::jsonb);
  v_id := (v_invoice ->> 'id')::uuid;
  if (select customer_id from public.invoices where id = v_id) <> '22222222-2222-4222-8222-222222222222'
    or (select customer_contact_id from public.invoices where id = v_id) <> '33333333-3333-4333-8333-333333333333'
    or (select source_quote_id from public.invoices where id = v_id) <> '44444444-4444-4444-8444-444444444444' then
    raise exception 'parties %', v_invoice;
  end if;
  if v_invoice ->> 'company_type' <> 'customer' or v_invoice ->> 'origin_type' <> 'quote' then
    raise exception 'read back %', v_invoice;
  end if;
  -- The app rounds VAT once per rate: 2006 * 21% = 421.26, so 421, not 2 * 211.
  if (select total_incl_cents from public.invoices where id = v_id) <> 2427 or (v_invoice ->> 'total')::bigint <> 2427 then
    raise exception 'totals %', v_invoice;
  end if;
  v_invoice := better_supabase.issue_invoice(v_id, date '2025-12-31');
  if v_invoice ->> 'identifier' <> '2025-1' then
    raise exception 'numbered %', v_invoice;
  end if;
  v_invoice := better_supabase.add_invoice_charge(v_id, 4000, 'EUR', 'Collection costs', '{"kind": "collection"}');
  if (v_invoice ->> 'balance')::bigint <> 6427 or (v_invoice ->> 'charged_total')::bigint <> 4000
    or v_invoice -> 'charges' -> 0 -> 'fields' ->> 'kind' <> 'collection' then
    raise exception 'charged %', v_invoice;
  end if;
  v_invoice := better_supabase.record_invoice_payment(v_id, 2427, 'EUR', now(), 'bank', 'tx-1');
  if (select status::text from public.invoices where id = v_id) <> 'sent' or (v_invoice ->> 'balance')::bigint <> 4000 then
    raise exception 'paid the total only %', v_invoice;
  end if;
  if (better_supabase.invoice_aging('${TENANT}', 'EUR', current_date) ->> 'outstanding')::bigint <> 4000 then
    raise exception 'aging %', better_supabase.invoice_aging('${TENANT}', 'EUR', current_date);
  end if;
  v_invoice := better_supabase.record_invoice_payment(v_id, 4000, 'EUR', now(), 'bank', 'tx-2');
  if (select status::text from public.invoices where id = v_id) <> 'paid' then
    raise exception 'paid %', v_invoice;
  end if;
end;
$$;`;

    await using stack = await liteStack({
      driver: "pglite",
      migrations: [
        ROLES,
        app,
        ...files
          .filter((file) => file.kind !== "data")
          .map((file) => file.contents),
      ],
      seed: [
        ...files
          .filter((file) => file.kind === "data")
          .map((file) => file.contents),
        check,
      ],
    });

    expect(stack.url).not.toBe("");
  });

  it("leaves the totals trigger out when the app owns the totals", () => {
    const sql = renderBlocks(["invoices"], {
      modules: { invoices: { options: { totals: "app" } } },
    })
      .filter((file) => file.module === "invoices")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).not.toContain("create trigger bsb_invoice_lines_totals_insert");
    expect(sql).toContain(
      "drop trigger if exists bsb_invoice_lines_totals_insert",
    );
    expect(sql).not.toContain(
      'create or replace function "better_supabase"."set_invoice_lines_recount"',
    );
    expect(() =>
      renderBlocks(["invoices"], {
        modules: { invoices: { options: { totals: "lines" } } },
      }),
    ).toThrow(/totals/);
  });
});
