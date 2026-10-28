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

// PGlite has no pgcrypto; the quote link needs random bytes and a sha256.
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

// The app's own quotes table: renamed columns, an enum status, and no
// company, contact, terms, note, origin or decision note columns. The
// module adds the send and total columns it is missing.
const APP = `
create type public.proposal_state as enum ('draft', 'sent', 'viewed', 'accepted', 'rejected', 'changes_requested', 'expired', 'withdrawn');

create table public.proposals (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  seq bigint not null,
  code text not null,
  revision integer not null default 1,
  supersedes_id uuid references public.proposals (id) on delete set null,
  title text not null,
  owner_user_id uuid,
  currency char(3) not null,
  state public.proposal_state not null default 'draft',
  valid_until date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  internal_ref text
);
`;

const OWN_TABLES = { "public.proposals": "app.sql" };

const BLOCKS: AnyBlocksConfig = {
  quotes: {
    tables: { quotes: "public.proposals" },
    columns: {
      quotes: {
        tenant: "org_id",
        number: "seq",
        identifier: "code",
        status: "state",
        companyType: null,
        companyId: null,
        contactType: null,
        contactId: null,
        terms: null,
        note: null,
        originType: null,
        originId: null,
        viewedAt: null,
        decisionNote: null,
        createdBy: null,
      },
    },
  },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

// The app's own line table: no discount, tax or creation columns, an enum
// product type, and a note table that points at line ids.
const APP_LINES = `
create type public.line_product as enum ('product_variant', 'service');

create table public.proposal_lines (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  proposal_id uuid not null references public.proposals (id) on delete cascade,
  product_type public.line_product,
  product_id text,
  label text not null,
  qty numeric(18, 4) not null,
  unit_amount bigint not null,
  position integer not null
);

create table public.line_notes (
  line_id uuid primary key references public.proposal_lines (id),
  body text not null
);
`;

const LINE_BLOCKS: AnyBlocksConfig = {
  quotes: {
    ...BLOCKS["quotes"],
    tables: { quotes: "public.proposals", lines: "public.proposal_lines" },
    columns: {
      ...BLOCKS["quotes"]?.columns,
      lines: {
        tenant: "org_id",
        parent: "proposal_id",
        description: "label",
        quantity: "qty",
        discountBps: null,
        taxRateBps: null,
        taxCode: null,
        createdAt: null,
      },
    },
  },
};

interface Over {
  readonly app: string;
  readonly blocks: AnyBlocksConfig;
  readonly own: Record<string, string>;
}

const QUOTES: Over = { app: APP, blocks: BLOCKS, own: OWN_TABLES };

async function run(check: string, over: Over = QUOTES): Promise<void> {
  const files = renderBlocks(["quotes"], {
    modules: over.blocks,
    ownTables: over.own,
  });

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      PGCRYPTO,
      over.app,
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

describe("quotes over the app's tables", BOOT, () => {
  it("creates, sends, revises and answers a quote in an enum status column", async () => {
    await expect(
      run(`do $$
declare
  v_quote jsonb;
  v_sent jsonb;
  v_revised jsonb;
  v_id uuid;
begin
  ${SERVICE}
  v_quote := better_supabase.create_quote('${TENANT}', '{"title": "Website", "currency": "eur"}'::jsonb,
    '[{"description": "Design", "quantity": 2, "unitAmount": "5000"}]'::jsonb);
  v_id := (v_quote ->> 'id')::uuid;
  if v_quote ->> 'status' <> 'draft' or (v_quote ->> 'total')::bigint <> 10000 then
    raise exception 'created %', v_quote;
  end if;
  perform better_supabase.update_quote(v_id, '{"title": "Website redesign"}'::jsonb);
  if (select title from public.proposals where id = v_id) <> 'Website redesign' then
    raise exception 'update missed the title';
  end if;
  v_sent := better_supabase.send_quote(v_id);
  if (better_supabase.public_quote(v_sent ->> 'token')) ->> 'status' <> 'viewed' then
    raise exception 'public_quote did not mark it viewed';
  end if;
  v_revised := better_supabase.revise_quote(v_id);
  if (v_revised ->> 'id')::uuid <> v_id or (v_revised ->> 'revision')::int <> 2 or (select state from public.proposals where id = v_id) <> 'draft' then
    raise exception 'revised %', v_revised;
  end if;
  perform better_supabase.send_quote(v_id);
  if (select array_agg(revision order by revision) from better_supabase.quote_versions where quote_id = v_id) <> array[1, 2] then
    raise exception 'versions %', better_supabase.quote_versions(v_id);
  end if;
  perform better_supabase.decide_quote(v_id, 'accepted', 'fine', 'Ann');
  if (select state from public.proposals where id = v_id) <> 'accepted' then
    raise exception 'decision missed';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("keeps the ids of the app's lines when it sets them again", async () => {
    await expect(
      run(
        `do $$
declare
  v_quote jsonb;
  v_id uuid;
  v_first uuid;
begin
  ${SERVICE}
  v_quote := better_supabase.create_quote('${TENANT}', '{"title": "Website", "currency": "EUR"}'::jsonb,
    '[{"description": "Design", "quantity": 2, "unitAmount": "5000", "product": {"type": "service", "id": "s1"}}, {"description": "Build", "quantity": 1, "unitAmount": "100"}]'::jsonb);
  v_id := (v_quote ->> 'id')::uuid;
  select id into v_first from public.proposal_lines where proposal_id = v_id and position = 1;
  insert into public.line_notes (line_id, body) values (v_first, 'kept');
  if (v_quote ->> 'total')::bigint <> 10100 then
    raise exception 'created %', v_quote;
  end if;
  perform better_supabase.set_quote_lines(v_id, '[{"description": "Design work", "quantity": 3, "unitAmount": "5000"}]'::jsonb);
  if (select count(*) from public.proposal_lines where proposal_id = v_id) <> 1
    or (select id from public.proposal_lines where proposal_id = v_id) <> v_first
    or (select label from public.proposal_lines where id = v_first) <> 'Design work'
    or (select total from public.proposals where id = v_id) <> 15000 then
    raise exception 'lines %', (select jsonb_agg(l) from public.proposal_lines l);
  end if;
end;
$$;`,
        {
          app: `${APP}${APP_LINES}`,
          blocks: LINE_BLOCKS,
          own: { ...OWN_TABLES, "public.proposal_lines": "app.sql" },
        },
      ),
    ).resolves.toBeUndefined();
  });

  it("writes line extras in the insert, so a check across them holds", async () => {
    await expect(
      run(
        `do $$
declare
  v_id uuid;
begin
  ${SERVICE}
  v_id := (better_supabase.create_quote('${TENANT}', '{"title": "Website", "currency": "EUR"}'::jsonb, null) ->> 'id')::uuid;
  perform better_supabase.set_quote_lines(v_id, '[{"description": "Intro", "quantity": 1, "unitAmount": "0", "fields": {"kind": "text"}}, {"description": "Build", "quantity": 1, "unitAmount": "100", "fields": {"line_type": "labor"}}]'::jsonb);
  if (select string_agg(kind || ':' || coalesce(line_type, '-'), ',' order by position) from public.proposal_lines where proposal_id = v_id) <> 'text:-,line:labor' then
    raise exception 'lines %', (select jsonb_agg(l) from public.proposal_lines l);
  end if;
end;
$$;`,
        {
          app: `${APP}${APP_LINES}
alter table public.proposal_lines add column kind text not null default 'line',
  add column line_type text,
  add constraint proposal_lines_kind check (kind <> 'line' or line_type is not null);`,
          blocks: {
            quotes: {
              ...LINE_BLOCKS["quotes"],
              options: {
                lineExtraColumns: {
                  kind: "text not null default 'line'",
                  line_type: "text",
                },
              },
            },
          },
          own: { ...OWN_TABLES, "public.proposal_lines": "app.sql" },
        },
      ),
    ).resolves.toBeUndefined();
  });

  it("maps statuses and skips a viewed status the app lacks", async () => {
    await expect(
      run(
        `do $$
declare
  v_id uuid;
  v_sent jsonb;
  v_public jsonb;
begin
  ${SERVICE}
  v_id := (better_supabase.create_quote('${TENANT}', '{"title": "Website", "currency": "EUR"}'::jsonb,
    '[{"description": "Design", "quantity": 1, "unitAmount": "5000"}]'::jsonb) ->> 'id')::uuid;
  v_sent := better_supabase.send_quote(v_id);
  if (select state::text from public.proposals where id = v_id) <> 'published' or v_sent ->> 'status' <> 'sent' then
    raise exception 'sent %', v_sent;
  end if;
  v_public := better_supabase.public_quote(v_sent ->> 'token');
  if v_public ->> 'status' <> 'sent' or (select state::text from public.proposals where id = v_id) <> 'published' then
    raise exception 'viewed %', v_public;
  end if;
  perform better_supabase.decide_quote(v_id, 'accepted', null, 'Ann');
  if (select state::text from public.proposals where id = v_id) <> 'accepted' then
    raise exception 'decision missed';
  end if;
end;
$$;`,
        {
          app: APP.replace(
            "('draft', 'sent', 'viewed', 'accepted', 'rejected', 'changes_requested', 'expired', 'withdrawn')",
            "('draft', 'published', 'accepted', 'rejected', 'changes_requested', 'expired', 'withdrawn')",
          ),
          blocks: {
            quotes: {
              ...BLOCKS["quotes"],
              values: {
                quotes: { status: { sent: "published", viewed: null } },
              },
            },
          },
          own: OWN_TABLES,
        },
      ),
    ).resolves.toBeUndefined();
  });

  it("refuses terms the app's table has no column for", async () => {
    await expect(
      run(`do $$
begin
  ${SERVICE}
  perform better_supabase.create_quote('${TENANT}', '{"title": "Website", "currency": "EUR", "terms": "net 30"}'::jsonb, null);
end;
$$;`),
    ).rejects.toThrow(/no terms column/);
  });
});
