import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const STAFF = "22222222-2222-4222-8222-222222222222";
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

const STAFF_CALL = `perform set_config('request.jwt.claims', '{"sub":"${STAFF}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${STAFF}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);`;

const MEMBER_CALL = `perform set_config('request.jwt.claims', '{"sub":"${MEMBER}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${MEMBER}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);`;

// Staff hold every key; a member holds none of the manage keys.
const KEYS = `
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$
  select coalesce(auth.uid() <> '${MEMBER}'::uuid, true) or permission not like '%.manage'
$$;
`;

const all = (statuses: readonly string[]) =>
  Object.fromEntries(
    statuses.map((from) => [from, statuses.filter((to) => to !== from)]),
  );

const QUOTE_STATUSES = [
  "draft",
  "sent",
  "viewed",
  "accepted",
  "rejected",
  "changes_requested",
  "expired",
  "withdrawn",
];

const INVOICE_STATUSES = [
  "draft",
  "issued",
  "partially_paid",
  "paid",
  "void",
  "uncollectible",
];

const BOOT = { timeout: 60_000 };

async function run(
  check: string,
  modules: AnyBlocksConfig,
  installed: readonly string[],
  app = "",
): Promise<void> {
  const files = renderBlocks(installed, { modules });

  const machineLast = [
    ...files.filter((file) => file.module !== "state-machine"),
    ...files.filter((file) => file.module === "state-machine"),
  ];

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      PGCRYPTO,
      app,
      ...machineLast
        .filter((file) => file.kind !== "data")
        .map((file) => file.contents),
    ],
    seed: [
      ...files
        .filter((file) => file.kind === "data")
        .map((file) => file.contents),
      KEYS,
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

const quoteMachine = (history?: object): AnyBlocksConfig => ({
  "state-machine": {
    options: {
      machines: {
        quote: {
          table: "better_supabase.quotes",
          column: "status",
          tenant: "tenant_id",
          initial: "draft",
          transitions: all(QUOTE_STATUSES),
          ...(history === undefined ? {} : { history }),
        },
      },
    },
  },
});

const appHistory = (ip: "text" | "inet"): string => `
create table public.quote_history (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  subject_id uuid not null,
  from_status text,
  to_status text not null,
  actor_user_id uuid,
  reason text,
  ip_address ${ip},
  created_at timestamptz not null default now()
);
`;

const sent = `v_id := (better_supabase.create_quote('${TENANT}', '{"title": "Website", "currency": "EUR"}'::jsonb,
    '[{"description": "Design", "unitAmount": "5000"}]'::jsonb) ->> 'id')::uuid;
  perform better_supabase.send_quote(v_id);`;

describe("an app history table with an IP column", BOOT, () => {
  it.each(["text", "inet"] as const)(
    "writes the actor's IP into a %s column",
    async (type) => {
      await expect(
        run(
          `do $$
declare
  v_id uuid;
begin
  ${SERVICE}
  ${sent}
  perform better_supabase.withdraw_quote(v_id, '{"name": "Wes", "ip": "198.51.100.4"}'::jsonb, 'Customer cancelled');
  if (select host(ip_address::inet) || ':' || reason from public.quote_history where to_status = 'withdrawn')
    is distinct from '198.51.100.4:Customer cancelled' then
    raise exception 'history %', (select jsonb_agg(h) from public.quote_history h);
  end if;
  if exists (select 1 from public.quote_history where to_status = 'sent' and (ip_address is not null or reason is not null)) then
    raise exception 'a change without an actor %', (select jsonb_agg(h) from public.quote_history h);
  end if;
end;
$$;`,
          quoteMachine({
            table: "public.quote_history",
            tenant: "tenant_id",
            ip: "ip_address",
          }),
          ["quotes", "state-machine"],
          appHistory(type),
        ),
      ).resolves.toBeUndefined();
    },
  );
});

describe("reasons and signers of quote answers", BOOT, () => {
  it("keeps the withdraw reason and the decision note in the history", async () => {
    await expect(
      run(
        `do $$
declare
  v_id uuid;
  v_quote jsonb;
begin
  ${STAFF_CALL}
  ${sent}
  perform better_supabase.withdraw_quote(v_id, null, 'Prices changed');
  perform better_supabase.revise_quote(v_id);
  perform better_supabase.send_quote(v_id);
  v_quote := better_supabase.decide_quote(v_id, 'rejected', 'Too expensive', null);
  if v_quote ->> 'decided_by' is not null then
    raise exception 'the caller signed %', v_quote;
  end if;
  if (select string_agg(from_status || '>' || to_status || ':' || coalesce(reason, '-'), ',' order by from_status, to_status) from better_supabase.status_history)
    <> 'draft>sent:-,draft>sent:-,sent>rejected:Too expensive,sent>withdrawn:Prices changed,withdrawn>draft:-' then
    raise exception 'history %', (select jsonb_agg(h) from better_supabase.status_history h);
  end if;
  perform better_supabase.revise_quote(v_id);
  perform better_supabase.send_quote(v_id);
  v_quote := better_supabase.decide_quote(v_id, 'accepted', null, 'Ann');
  if v_quote ->> 'decided_by' <> 'Ann'
    or (select reason from better_supabase.status_history where to_status = 'accepted') is not null then
    raise exception 'signer % %', v_quote, (select jsonb_agg(h) from better_supabase.status_history h);
  end if;
end;
$$;`,
        quoteMachine(),
        ["quotes", "state-machine"],
      ),
    ).resolves.toBeUndefined();
  });

  it("names the actor as the signer without by", async () => {
    await expect(
      run(
        `do $$
declare
  v_id uuid;
begin
  ${SERVICE}
  ${sent}
  if better_supabase.decide_quote(v_id, 'accepted', null, null, null, '{"email": "cleo@example.com"}'::jsonb) ->> 'decided_by' <> 'cleo@example.com' then
    raise exception 'actor signer';
  end if;
end;
$$;`,
        {},
        ["quotes"],
      ),
    ).resolves.toBeUndefined();
  });

  it("refuses a withdraw with a reason by a member without the key", async () => {
    await expect(
      run(
        `do $$
declare
  v_id uuid;
begin
  ${SERVICE}
  ${sent}
  ${MEMBER_CALL}
  perform better_supabase.withdraw_quote(v_id, null, 'Mine now');
end;
$$;`,
        { quotes: { permissions: { withdraw: "quotes.manage" } } },
        ["quotes"],
      ),
    ).rejects.toThrow(/no such quote you can edit/);
  });
});

const quotesSql = (modules: AnyBlocksConfig): string =>
  renderBlocks(["quotes", "notifications"], { modules })
    .filter((file) => file.module === "quotes")
    .map((file) => file.contents)
    .join("\n");

describe("the owner notification on an answer", () => {
  it("is sent by default with a subject label, and not with notifications off", () => {
    expect(quotesSql({})).toContain("'quote.decided'");
    expect(quotesSql({})).toContain(`'subject_label', v_row."identifier"`);
    expect(
      quotesSql({ quotes: { options: { notifications: false } } }),
    ).not.toContain("'quote.decided'");
  });
});

const INVOICE_MACHINE: AnyBlocksConfig = {
  "state-machine": {
    options: {
      machines: {
        invoice: {
          table: "better_supabase.invoices",
          column: "status",
          tenant: "tenant_id",
          initial: "draft",
          transitions: all(INVOICE_STATUSES),
        },
      },
    },
  },
};

describe("a reason on a recorded payment", BOOT, () => {
  it("keeps the reason of the status change a payment causes", async () => {
    await expect(
      run(
        `do $$
declare
  v_id uuid;
begin
  ${SERVICE}
  v_id := (better_supabase.create_invoice('${TENANT}', '{"title": "Repair", "currency": "EUR"}'::jsonb,
    '[{"description": "Part", "quantity": 1, "unitAmount": "1000"}]'::jsonb) ->> 'id')::uuid;
  perform better_supabase.issue_invoice(v_id, current_date, null);
  perform better_supabase.record_invoice_payment(v_id, 1000, 'EUR', now(), 'card', 'pi-1');
  perform better_supabase.record_invoice_payment(v_id, -1000, 'EUR', now(), 'card', 're-1', null, null, 'Payment refunded via Stripe');
  if (select string_agg(from_status || '>' || to_status || ':' || coalesce(reason, '-'), ',' order by from_status, to_status) from better_supabase.status_history)
    <> 'draft>issued:-,issued>paid:-,paid>issued:Payment refunded via Stripe' then
    raise exception 'history %', (select jsonb_agg(h) from better_supabase.status_history h);
  end if;
end;
$$;`,
        INVOICE_MACHINE,
        ["invoices", "state-machine"],
      ),
    ).resolves.toBeUndefined();
  });

  it("refuses a payment with a reason by a member without the key", async () => {
    await expect(
      run(
        `do $$
declare
  v_id uuid;
begin
  ${SERVICE}
  v_id := (better_supabase.create_invoice('${TENANT}', '{"title": "Repair", "currency": "EUR"}'::jsonb,
    '[{"description": "Part", "quantity": 1, "unitAmount": "1000"}]'::jsonb) ->> 'id')::uuid;
  perform better_supabase.issue_invoice(v_id, current_date, null);
  ${MEMBER_CALL}
  perform better_supabase.record_invoice_payment(v_id, 1000, 'EUR', now(), 'card', 'pi-1', null, null, 'Paid');
end;
$$;`,
        { invoices: { permissions: { payment: "invoices.manage" } } },
        ["invoices"],
      ),
    ).rejects.toThrow(/no such invoice you can edit/);
  });
});
