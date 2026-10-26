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
): Promise<void> {
  const files = renderBlocks(["invoices"], { modules, ownTables: OWN_TABLES });

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
});
