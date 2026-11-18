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

const STATUSES = [
  "draft",
  "issued",
  "partially_paid",
  "paid",
  "void",
  "uncollectible",
  "credited",
];

const BLOCKS: AnyBlocksConfig = {
  invoices: { options: { creditedStatus: true } },
  "state-machine": {
    options: {
      machines: {
        invoice: {
          table: "better_supabase.invoices",
          column: "status",
          tenant: "tenant_id",
          initial: "draft",
          transitions: Object.fromEntries(
            STATUSES.map((from) => [
              from,
              STATUSES.filter((to) => to !== from),
            ]),
          ),
        },
      },
    },
  },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);
  perform set_config('request.jwt.claim.sub', '', true);`;

const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["outbox", "invoices", "state-machine"], {
    modules: BLOCKS,
  });

  const invoicesFirst = [
    ...files.filter((file) => file.module !== "state-machine"),
    ...files.filter((file) => file.module === "state-machine"),
  ];

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      ...invoicesFirst
        .filter((file) => file.kind === "schema")
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

const issued = (title: string): string =>
  `(better_supabase.issue_invoice((better_supabase.create_invoice('${TENANT}', '{"title": "${title}", "currency": "EUR"}'::jsonb,
    '[{"description": "Work", "quantity": 1, "unitAmount": "10000"}]'::jsonb) ->> 'id')::uuid, current_date) ->> 'id')::uuid`;

// Issues a credit note of `amount` on `invoice` and returns its id.
const credit = (invoice: string, amount: number): string =>
  `(better_supabase.issue_invoice((better_supabase.credit_invoice(${invoice}, '[{"description": "Credit", "quantity": 1, "unitAmount": "${amount}"}]'::jsonb, 'credit') ->> 'id')::uuid, current_date) ->> 'id')::uuid`;

const status = (id: string): string =>
  `(select x.status from better_supabase.invoices x where x.id = ${id})`;

const events = (type: string, id: string): string =>
  `(select count(*) from better_supabase.outbox_events e where e.type = '${type}' and e.payload ->> 'invoiceId' = ${id}::text and e.payload ->> 'organizationId' = '${TENANT}')`;

describe("the credited invoice status", BOOT, () => {
  it("credits unpaid and paid invoices, leaves a partial credit and reverts a voided credit note", async () => {
    await expect(
      run(`do $$
declare
  v_unpaid uuid;
  v_paid uuid;
  v_partial uuid;
  v_voided uuid;
  v_note uuid;
begin
  ${SERVICE}
  v_unpaid := ${issued("Unpaid")};
  perform ${credit("v_unpaid", 10_000)};
  if ${status("v_unpaid")} <> 'credited' or (select paid_at from better_supabase.invoices where id = v_unpaid) is not null then
    raise exception 'unpaid: %', ${status("v_unpaid")};
  end if;
  if ${events("invoice.credited", "v_unpaid")} <> 1 or ${events("invoice.paid", "v_unpaid")} <> 0 then
    raise exception 'unpaid events';
  end if;
  if not exists (select 1 from better_supabase.status_history h where h.subject_id = v_unpaid::text and h.from_status = 'issued' and h.to_status = 'credited')
    or not exists (select 1 from better_supabase.outbox_events e where e.type = 'status.changed' and e.payload ->> 'subjectId' = v_unpaid::text and e.payload ->> 'to' = 'credited') then
    raise exception 'unpaid history';
  end if;

  v_paid := ${issued("Paid")};
  perform better_supabase.record_invoice_payment(v_paid, 10000, 'EUR', now(), 'bank', 'tx-paid');
  perform ${credit("v_paid", 10_000)};
  if ${status("v_paid")} <> 'credited' or ${events("invoice.paid", "v_paid")} <> 1 then
    raise exception 'paid then credited: % %', ${status("v_paid")}, ${events("invoice.paid", "v_paid")};
  end if;
  perform better_supabase.record_invoice_payment(v_paid, -10000, 'EUR', now(), 'bank', 'tx-refund');
  if ${status("v_paid")} <> 'credited' or (better_supabase.get_invoice(v_paid) ->> 'balance')::bigint <> 0 then
    raise exception 'refund on a credited invoice: %', better_supabase.get_invoice(v_paid);
  end if;

  v_partial := ${issued("Partial")};
  perform ${credit("v_partial", 4000)};
  if ${status("v_partial")} <> 'partially_paid' then
    raise exception 'partial: %', ${status("v_partial")};
  end if;

  v_voided := ${issued("Voided")};
  v_note := ${credit("v_voided", 10_000)};
  if ${status("v_voided")} <> 'credited' then
    raise exception 'before the void: %', ${status("v_voided")};
  end if;
  perform better_supabase.void_invoice(v_note, 'wrong invoice');
  if ${status("v_voided")} <> 'issued' or (select credited_total from better_supabase.invoices where id = v_voided) <> 0 then
    raise exception 'after the void: %', ${status("v_voided")};
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
