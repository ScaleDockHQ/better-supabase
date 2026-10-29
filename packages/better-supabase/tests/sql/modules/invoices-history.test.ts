import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const STAFF = "22222222-2222-4222-8222-222222222222";

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
];

const MACHINE: AnyBlocksConfig = {
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
  const files = renderBlocks(["invoices", "state-machine"], {
    modules: MACHINE,
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

const ACTOR = `'{"id": "${STAFF}", "name": "Sam", "email": "sam@example.com"}'::jsonb`;

const issued = (title: string): string =>
  `(better_supabase.issue_invoice((better_supabase.create_invoice('${TENANT}', '{"title": "${title}", "currency": "EUR"}'::jsonb,
    '[{"description": "Work", "quantity": 1, "unitAmount": "10000"}]'::jsonb) ->> 'id')::uuid, current_date) ->> 'id')::uuid`;

describe("invoice status history from the block's own writes", BOOT, () => {
  it("keeps the reason and actor of a void, write-off, reversal and charge", async () => {
    await expect(
      run(`do $$
declare
  v_void uuid;
  v_lost uuid;
  v_paid uuid;
  v_payment uuid;
  v_charged uuid;
  v_charge uuid;
  v_row record;
begin
  ${SERVICE}
  v_void := ${issued("Void")};
  perform better_supabase.void_invoice(v_void, 'sent in error', ${ACTOR});
  select * into v_row from better_supabase.status_history where subject_id = v_void::text and to_status = 'void';
  if v_row.reason is distinct from 'sent in error' or v_row.actor_user_id is distinct from '${STAFF}'::uuid or v_row.actor_name is distinct from 'Sam' then
    raise exception 'void %', row_to_json(v_row);
  end if;

  v_lost := ${issued("Lost")};
  perform better_supabase.write_off_invoice(v_lost, 'customer went bankrupt', ${ACTOR});
  select * into v_row from better_supabase.status_history where subject_id = v_lost::text and to_status = 'uncollectible';
  if v_row.reason is distinct from 'customer went bankrupt' or v_row.actor_name is distinct from 'Sam' then
    raise exception 'write-off %', row_to_json(v_row);
  end if;

  v_paid := ${issued("Paid")};
  v_payment := (better_supabase.record_invoice_payment(v_paid, 10000, 'EUR', now(), 'bank', 'tx-1') -> 'payments' -> 0 ->> 'id')::uuid;
  perform better_supabase.reverse_invoice_payment(v_payment, 'chargeback', ${ACTOR});
  select * into v_row from better_supabase.status_history where subject_id = v_paid::text and from_status = 'paid';
  if v_row.reason is distinct from 'chargeback' or v_row.actor_name is distinct from 'Sam' then
    raise exception 'reversal %', row_to_json(v_row);
  end if;

  v_charged := ${issued("Charged")};
  perform better_supabase.record_invoice_payment(v_charged, 10000, 'EUR', now(), 'bank', 'tx-2');
  v_charge := (better_supabase.add_invoice_charge(v_charged, 500, 'EUR', 'Late fee', actor => ${ACTOR}) -> 'charges' -> 0 ->> 'id')::uuid;
  select * into v_row from better_supabase.status_history where subject_id = v_charged::text and from_status = 'paid';
  if v_row.actor_name is distinct from 'Sam' or v_row.reason is not null then
    raise exception 'charge %', row_to_json(v_row);
  end if;
  if v_charge is not null then
    perform better_supabase.remove_invoice_charge(v_charge, '{"name": "Rita"}'::jsonb);
    if (select actor_name from better_supabase.status_history where subject_id = v_charged::text and from_status = 'partially_paid') is distinct from 'Rita' then
      raise exception 'charge removal %', (select jsonb_agg(h) from better_supabase.status_history h where subject_id = v_charged::text);
    end if;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("refuses an actor that isn't an object", async () => {
    await expect(
      run(`do $$
begin
  ${SERVICE}
  perform better_supabase.void_invoice(${issued("Void")}, 'oops', '"Sam"'::jsonb);
end;
$$;`),
    ).rejects.toThrow(/actor must be an object/);
  });
});
