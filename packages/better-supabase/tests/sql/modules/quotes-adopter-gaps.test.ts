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

const ANON = `perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('request.jwt.claim.role', 'anon', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.headers', '{"x-forwarded-for": "203.0.113.9", "user-agent": "Browser/1"}', true);`;

const MEMBER_CALL = `perform set_config('request.jwt.claims', '{"sub":"${MEMBER}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${MEMBER}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);`;

// A member who may write quotes in the tenant, but holds no quotes.manage.
const MEMBER_KEYS = `
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$
  select scope_id = '${TENANT}'::uuid and permission <> 'quotes.manage'
$$;
`;

const STATUSES = [
  "draft",
  "sent",
  "viewed",
  "accepted",
  "rejected",
  "changes_requested",
  "expired",
  "withdrawn",
];

const MACHINE: AnyBlocksConfig = {
  "state-machine": {
    options: {
      machines: {
        quote: {
          table: "better_supabase.quotes",
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

const BOOT = { timeout: 60_000 };

async function run(
  check: string,
  modules: AnyBlocksConfig,
  installed: readonly string[] = ["quotes"],
  setup = "",
): Promise<void> {
  const files = renderBlocks(installed, { modules });

  const quotesFirst = [
    ...files.filter((file) => file.module !== "state-machine"),
    ...files.filter((file) => file.module === "state-machine"),
  ];

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      PGCRYPTO,
      ...quotesFirst
        .filter((file) => file.kind !== "data")
        .map((file) => file.contents),
    ],
    seed: [
      ...files
        .filter((file) => file.kind === "data")
        .map((file) => file.contents),
      setup,
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

const sqlOf = (modules: AnyBlocksConfig): string =>
  renderBlocks(["quotes"], { modules })
    .filter((file) => file.module === "quotes")
    .map((file) => file.contents)
    .join("\n");

// The app counts the totals: a fixed discount per line and a VAT regime that
// keeps the line rates but counts no VAT.
const APP_TOTALS: AnyBlocksConfig = {
  quotes: {
    options: {
      totals: "app",
      extraColumns: { vat_regime: "text not null default 'standard'" },
      lineExtraColumns: { discount_amount_cents: "bigint not null default 0" },
    },
  },
};

const APP_RECOUNT = `
create or replace function public.recount_quote() returns trigger language plpgsql as $$
declare
  v_quote uuid := coalesce(new.parent_id, old.parent_id);
  v_net bigint;
  v_tax bigint;
begin
  select coalesce(sum(round(l.quantity * l.unit_amount) - l.discount_amount_cents), 0),
    coalesce(sum(round((round(l.quantity * l.unit_amount) - l.discount_amount_cents) * l.tax_rate_bps / 10000.0)), 0)
    into v_net, v_tax
  from better_supabase.quote_lines l where l.parent_id = v_quote and (not l.optional or l.selected);
  update better_supabase.quotes q set subtotal = v_net,
    tax_total = case when q.vat_regime = 'standard' then v_tax else 0 end,
    total = v_net + case when q.vat_regime = 'standard' then v_tax else 0 end
  where q.id = v_quote;
  return null;
end;
$$;
create trigger app_recount after insert or update or delete on better_supabase.quote_lines
for each row execute function public.recount_quote();
`;

describe("quotes with the app's own totals", BOOT, () => {
  it("keeps the app's totals, a fixed line discount and a reverse charge", async () => {
    await expect(
      run(
        `do $$
declare
  v_quote jsonb;
  v_id uuid;
  v_totals jsonb;
begin
  ${SERVICE}
  v_quote := better_supabase.create_quote('${TENANT}', '{"title": "Work", "currency": "EUR", "depositBps": 1000, "fields": {"vat_regime": "reverse_charge"}}'::jsonb,
    '[{"description": "Work", "quantity": 1, "unitAmount": "10000", "taxRateBps": 2100, "fields": {"discount_amount_cents": 500}}]'::jsonb);
  v_id := (v_quote ->> 'id')::uuid;
  if (select (subtotal, tax_total, total, deposit_due) from better_supabase.quotes where id = v_id)
    is distinct from (9500::bigint, 0::bigint, 9500::bigint, 950::bigint) then
    raise exception 'app totals %', (select to_jsonb(q) from better_supabase.quotes q where id = v_id);
  end if;
  v_totals := better_supabase.set_quote_lines(v_id, '[{"description": "Work", "quantity": 2, "unitAmount": "10000", "taxRateBps": 2100, "fields": {"discount_amount_cents": 500}}]'::jsonb);
  if v_totals ->> 'total' <> '19500' or v_totals ->> 'taxTotal' <> '0' then
    raise exception 'setter totals %', v_totals;
  end if;
  perform better_supabase.update_quote(v_id, '{"depositAmount": "3000", "depositBps": null}'::jsonb);
  if (select deposit_due from better_supabase.quotes where id = v_id) <> 3000 then
    raise exception 'deposit due follows the app total';
  end if;
  if to_regprocedure('better_supabase.set_quote_lines_recount(uuid)') is not null then
    raise exception 'the block recount is installed';
  end if;
  perform better_supabase.send_quote(v_id);
  update better_supabase.quote_lines set selected = true where parent_id = v_id;
  perform better_supabase.decide_quote(v_id, 'accepted', null, 'Ann');
  begin
    update better_supabase.quotes set total = 1 where id = v_id;
    raise exception 'an accepted quote changed its totals';
  exception when sqlstate '55000' then
    null;
  end;
end;
$$;`,
        APP_TOTALS,
        ["quotes"],
        APP_RECOUNT,
      ),
    ).resolves.toBeUndefined();
  });

  it("refuses a totals change on an accepted quote", async () => {
    await expect(
      run(
        `do $$
declare
  v_id uuid;
begin
  ${SERVICE}
  v_id := (better_supabase.create_quote('${TENANT}', '{"title": "Work", "currency": "EUR"}'::jsonb,
    '[{"description": "Work", "unitAmount": "10000"}]'::jsonb) ->> 'id')::uuid;
  perform better_supabase.send_quote(v_id);
  perform better_supabase.decide_quote(v_id, 'accepted', null, 'Ann');
  update better_supabase.quotes set subtotal = 1, total = 1 where id = v_id;
end;
$$;`,
        APP_TOTALS,
        ["quotes"],
        APP_RECOUNT,
      ),
    ).rejects.toThrow(/totals of an answered, expired or withdrawn quote/);
  });

  it("recounts by default and refuses an unknown totals mode", () => {
    const sql = sqlOf({});
    expect(sql).toContain("set_quote_lines_recount");
    expect(sql).not.toContain("quotes_app_totals");
    expect(sqlOf(APP_TOTALS)).not.toContain("set_quote_lines_recount(v_row");
    expect(() => sqlOf({ quotes: { options: { totals: "lines" } } })).toThrow(
      /totals must be "block" or "app"/,
    );
  });
});

const VERSION_EXTRAS: AnyBlocksConfig = {
  quotes: {
    options: {
      workingCopy: true,
      versionLines: true,
      lineExtraColumns: { line_type: "text", stock_mode: "text" },
      versionLineExtraColumns: {
        line_type: "text",
        stock_mode: "text",
        shown_unit: "text",
      },
    },
  },
};

describe("quote version lines with the app's line columns", BOOT, () => {
  it("copies the line columns the version lines also have on publish", async () => {
    await expect(
      run(
        `do $$
declare
  v_id uuid;
begin
  ${SERVICE}
  alter table better_supabase.quote_version_lines add constraint typed check (line_type is not null);
  v_id := (better_supabase.create_quote('${TENANT}', '{"title": "Website", "currency": "EUR"}'::jsonb,
    '[{"description": "Design", "unitAmount": "5000", "fields": {"line_type": "labor", "stock_mode": "none"}},
      {"description": "Panel", "unitAmount": "900", "fields": {"line_type": "product", "stock_mode": "reserve"}}]'::jsonb) ->> 'id')::uuid;
  perform better_supabase.send_quote(v_id);
  if (select string_agg(line_type || ':' || stock_mode || ':' || coalesce(shown_unit, '-'), ',' order by position) from better_supabase.quote_version_lines)
    <> 'labor:none:-,product:reserve:-' then
    raise exception 'version lines %', (select jsonb_agg(l) from better_supabase.quote_version_lines l);
  end if;
end;
$$;`,
        VERSION_EXTRAS,
      ),
    ).resolves.toBeUndefined();
  });

  it("leaves the version lines as they were without the option", () => {
    const sql = sqlOf({
      quotes: { options: { workingCopy: true, versionLines: true } },
    });

    expect(sql).not.toContain("shown_unit");
    expect(sqlOf(VERSION_EXTRAS)).toContain('"shown_unit" text');
  });
});

const FINER: AnyBlocksConfig = {
  quotes: {
    permissions: {
      send: "quotes.manage",
      decide: "quotes.manage",
      withdraw: "quotes.manage",
    },
  },
};

const memberQuote = `v_id := (better_supabase.create_quote('${TENANT}', '{"title": "Website", "currency": "EUR"}'::jsonb,
    '[{"description": "Design", "unitAmount": "5000"}]'::jsonb) ->> 'id')::uuid;`;

describe("finer quote keys", BOOT, () => {
  it("lets a member edit but not send, decide or withdraw", async () => {
    await expect(
      run(
        `do $$
declare
  v_id uuid;
begin
  ${MEMBER_CALL}
  ${memberQuote}
  perform better_supabase.update_quote(v_id, '{"title": "Website v2"}'::jsonb);
  begin
    perform better_supabase.send_quote(v_id);
    raise exception 'a member sent the quote';
  exception when sqlstate 'P0002' then
    null;
  end;
  ${SERVICE}
  perform better_supabase.send_quote(v_id);
  ${MEMBER_CALL}
  begin
    perform better_supabase.decide_quote(v_id, 'accepted', null, 'Ann');
    raise exception 'a member decided the quote';
  exception when sqlstate 'P0002' then
    null;
  end;
  begin
    perform better_supabase.withdraw_quote(v_id);
    raise exception 'a member withdrew the quote';
  exception when sqlstate 'P0002' then
    null;
  end;
  perform better_supabase.revise_quote(v_id);
end;
$$;`,
        FINER,
        ["quotes"],
        MEMBER_KEYS,
      ),
    ).resolves.toBeUndefined();
  });

  it("falls back to the write key", async () => {
    await expect(
      run(
        `do $$
declare
  v_id uuid;
begin
  ${MEMBER_CALL}
  ${memberQuote}
  perform better_supabase.send_quote(v_id);
  perform better_supabase.withdraw_quote(v_id);
end;
$$;`,
        {},
        ["quotes"],
        MEMBER_KEYS,
      ),
    ).resolves.toBeUndefined();
  });
});

const RESEND: AnyBlocksConfig = { quotes: { options: { resend: true } } };

const declined = (status: string): string =>
  `update better_supabase.quotes set status = '${status}', valid_until = current_date - 1 where id = v_id;`;

describe("sending a declined quote again", BOOT, () => {
  it("sends a rejected, withdrawn or expired quote in one call", async () => {
    await expect(
      run(
        `do $$
declare
  v_id uuid;
  v_token text;
  v_sent jsonb;
begin
  ${SERVICE}
  v_id := (better_supabase.create_quote('${TENANT}', '{"title": "Website", "currency": "EUR"}'::jsonb,
    '[{"description": "Design", "unitAmount": "5000"}]'::jsonb) ->> 'id')::uuid;
  v_token := better_supabase.send_quote(v_id) ->> 'token';
  ${ANON}
  perform better_supabase.respond_to_quote(v_token, 'rejected', 'Cleo', 'too much');
  ${SERVICE}
  v_sent := better_supabase.send_quote(v_id, '{"name": "Sam"}'::jsonb);
  if v_sent ->> 'status' <> 'sent' or (v_sent ->> 'revision')::integer <> 2 or v_sent ->> 'decided_by' is not null then
    raise exception 'resent %', v_sent;
  end if;
  perform better_supabase.withdraw_quote(v_id);
  v_sent := better_supabase.send_quote(v_id);
  ${declined("expired")}
  v_sent := better_supabase.send_quote(v_id);
  if (v_sent ->> 'revision')::integer <> 4 or (v_sent ->> 'valid_until')::date < current_date + 30 then
    raise exception 'resent expired %', v_sent;
  end if;
  if exists (select 1 from better_supabase.status_history where to_status = 'draft') then
    raise exception 'a draft step %', (select jsonb_agg(h) from better_supabase.status_history h);
  end if;
  if (select actor_name from better_supabase.status_history where from_status = 'rejected') is distinct from 'Sam' then
    raise exception 'resend actor %', (select jsonb_agg(h) from better_supabase.status_history h);
  end if;
end;
$$;`,
        { ...RESEND, ...MACHINE },
        ["quotes", "state-machine"],
      ),
    ).resolves.toBeUndefined();
  });

  it("refuses a declined quote without the option", async () => {
    await expect(
      run(
        `do $$
declare
  v_id uuid;
begin
  ${SERVICE}
  v_id := (better_supabase.create_quote('${TENANT}', '{"title": "Website", "currency": "EUR"}'::jsonb,
    '[{"description": "Design", "unitAmount": "5000"}]'::jsonb) ->> 'id')::uuid;
  perform better_supabase.send_quote(v_id);
  perform better_supabase.decide_quote(v_id, 'rejected', null, 'Ann');
  perform better_supabase.send_quote(v_id);
end;
$$;`,
        {},
      ),
    ).rejects.toThrow(/the quote was already sent/);
  });

  it("refuses a resend by a member without the send key", async () => {
    await expect(
      run(
        `do $$
declare
  v_id uuid;
begin
  ${SERVICE}
  v_id := (better_supabase.create_quote('${TENANT}', '{"title": "Website", "currency": "EUR"}'::jsonb,
    '[{"description": "Design", "unitAmount": "5000"}]'::jsonb) ->> 'id')::uuid;
  perform better_supabase.send_quote(v_id);
  perform better_supabase.decide_quote(v_id, 'rejected', null, 'Ann');
  ${MEMBER_CALL}
  perform better_supabase.send_quote(v_id);
end;
$$;`,
        { quotes: { ...RESEND["quotes"], ...FINER["quotes"] } },
        ["quotes"],
        MEMBER_KEYS,
      ),
    ).rejects.toThrow(/no such quote you can edit/);
  });

  it("withdraws an expired quote by default", async () => {
    await expect(
      run(
        `do $$
declare
  v_id uuid;
begin
  ${SERVICE}
  v_id := (better_supabase.create_quote('${TENANT}', '{"title": "Website", "currency": "EUR"}'::jsonb,
    '[{"description": "Design", "unitAmount": "5000"}]'::jsonb) ->> 'id')::uuid;
  perform better_supabase.send_quote(v_id);
  ${declined("expired")}
  if better_supabase.withdraw_quote(v_id) ->> 'status' <> 'withdrawn' then
    raise exception 'not withdrawn';
  end if;
end;
$$;`,
        {},
      ),
    ).resolves.toBeUndefined();
  });
});

describe("actors on every quote status change", BOOT, () => {
  it("writes the history with the actor of each change", async () => {
    await expect(
      run(
        `do $$
declare
  v_id uuid;
  v_token text;
  v_row record;
begin
  ${SERVICE}
  v_id := (better_supabase.create_quote('${TENANT}', '{"title": "Website", "currency": "EUR"}'::jsonb,
    '[{"description": "Design", "unitAmount": "5000"}]'::jsonb) ->> 'id')::uuid;
  v_token := better_supabase.send_quote(v_id, '{"id": "${STAFF}", "name": "Sam"}'::jsonb) ->> 'token';
  ${ANON}
  perform better_supabase.public_quote(v_token);
  select * into v_row from better_supabase.status_history where to_status = 'viewed';
  if v_row.actor_name is not null or host(v_row.ip_address) is distinct from '203.0.113.9' or v_row.user_agent is distinct from 'Browser/1' then
    raise exception 'viewed by link %', row_to_json(v_row);
  end if;
  ${SERVICE}
  perform better_supabase.withdraw_quote(v_id, '{"name": "Wes"}'::jsonb);
  perform better_supabase.revise_quote(v_id, '{"name": "Rae"}'::jsonb);
  perform better_supabase.send_quote(v_id, '{"name": "Sam"}'::jsonb);
  perform better_supabase.portal_quote(v_id, '{"name": "Cleo", "email": "cleo@example.com", "ip": "198.51.100.4"}'::jsonb);
  if not exists (select 1 from better_supabase.status_history where to_status = 'viewed' and actor_name = 'Cleo' and host(ip_address) = '198.51.100.4') then
    raise exception 'viewed in the app portal %', (select jsonb_agg(h) from better_supabase.status_history h);
  end if;
  update better_supabase.quotes set valid_until = current_date - 1 where id = v_id;
  perform better_supabase.expire_quotes();
  select * into v_row from better_supabase.status_history where to_status = 'expired';
  if v_row.actor_name is not null or v_row.actor_user_id is not null then
    raise exception 'expiry inherited an actor %', row_to_json(v_row);
  end if;
  if (select string_agg(coalesce(actor_name, '-'), ',' order by actor_name) from better_supabase.status_history where to_status in ('withdrawn', 'draft'))
    <> 'Rae,Wes' then
    raise exception 'staff actors %', (select jsonb_agg(h) from better_supabase.status_history h);
  end if;
end;
$$;`,
        MACHINE,
        ["quotes", "state-machine"],
      ),
    ).resolves.toBeUndefined();
  });

  it("refuses an actor from a caller that isn't the service role", async () => {
    await expect(
      run(
        `do $$
declare
  v_id uuid;
begin
  ${SERVICE}
  v_id := (better_supabase.create_quote('${TENANT}', '{"title": "Website", "currency": "EUR"}'::jsonb,
    '[{"description": "Design", "unitAmount": "5000"}]'::jsonb) ->> 'id')::uuid;
  perform better_supabase.send_quote(v_id);
  ${MEMBER_CALL}
  perform better_supabase.portal_quote(v_id, '{"name": "Someone else"}'::jsonb);
end;
$$;`,
        {},
        ["quotes"],
        MEMBER_KEYS,
      ),
    ).rejects.toThrow(/only the service role names who opened a quote/);
  });
});
