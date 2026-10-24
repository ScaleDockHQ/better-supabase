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

// The app's own feed table: renamed columns, no unique event id, and no actor
// or summary columns.
const APP = `
create table public.feed (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  event_key text not null,
  kind text not null,
  record_type text,
  record_id text,
  payload jsonb not null default '{}'::jsonb,
  happened_at timestamptz not null default now(),
  notes text
);
`;

const OWN_TABLES = { "public.feed": "app.sql" };

const BLOCKS: AnyBlocksConfig = {
  timeline: {
    tables: { activity: "public.feed" },
    columns: {
      activity: {
        tenant: "org_id",
        event: "event_key",
        type: "kind",
        subjectType: "record_type",
        subjectId: "record_id",
        data: "payload",
        occurredAt: "happened_at",
        actor: null,
        summary: null,
      },
    },
  },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["memberships", "permissions", "timeline"], {
    modules: BLOCKS,
    ownTables: OWN_TABLES,
  });

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
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

const BATCH = `'{"entries": [
  {"event_id": "e1", "organization_id": "${TENANT}", "type": "deal.won", "actor_id": "22222222-2222-4222-8222-222222222222", "summary": "Won", "subject_type": "deal", "subject_id": "d1", "occurred_at": "2099-01-01T10:00:00Z"},
  {"event_id": "e2", "organization_id": "${TENANT}", "type": "deal.lost", "subject_type": "deal", "subject_id": "d2", "occurred_at": "2099-01-02T10:00:00Z"}
]}'::jsonb`;

describe("timeline over the app's tables", BOOT, () => {
  it("records a replayed batch once and lists it", async () => {
    await expect(
      run(`do $$
declare
  v_rows jsonb;
begin
  ${SERVICE}
  if better_supabase.record_activity(${BATCH}) <> 2 then
    raise exception 'first batch';
  end if;
  if better_supabase.record_activity(${BATCH}) <> 0 then
    raise exception 'the replay wrote rows';
  end if;
  v_rows := better_supabase.list_activity('${TENANT}');
  if jsonb_array_length(v_rows) <> 2 or v_rows -> 0 ->> 'event_key' <> 'e2' then
    raise exception 'list_activity %', v_rows;
  end if;
  v_rows := better_supabase.list_activity('${TENANT}', 'deal', 'd1');
  if jsonb_array_length(v_rows) <> 1 or v_rows -> 0 -> 'payload' <> '{}'::jsonb then
    raise exception 'subject timeline %', v_rows;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("refuses a caller other than the service role", async () => {
    await expect(
      run(`do $$
begin
  perform set_config('request.jwt.claims', '{"role":"authenticated"}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform better_supabase.record_activity(${BATCH});
end;
$$;`),
    ).rejects.toThrow(/Only the service role records activity/);
  });
});
