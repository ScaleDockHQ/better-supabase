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

async function run(check: string): Promise<void> {
  const files = renderBlocks(["quotes"], {
    modules: BLOCKS,
    ownTables: OWN_TABLES,
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
  if (v_revised ->> 'revision')::int <> 2 or (select state from public.proposals where id = v_id) <> 'withdrawn' then
    raise exception 'revised %', v_revised;
  end if;
  perform better_supabase.send_quote((v_revised ->> 'id')::uuid);
  perform better_supabase.decide_quote((v_revised ->> 'id')::uuid, 'accepted', 'fine', 'Ann');
  if (select state from public.proposals where id = (v_revised ->> 'id')::uuid) <> 'accepted' then
    raise exception 'decision missed';
  end if;
end;
$$;`),
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
