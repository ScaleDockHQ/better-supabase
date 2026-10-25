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

// The app's own activity tables: renamed columns, an enum type, and no
// duration, external ref, author, update time or link position.
const APP = `
create type public.activity_kind as enum ('call', 'email', 'meeting', 'note', 'task');

create table public.activities (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  kind public.activity_kind not null,
  title text not null,
  body text,
  outcome text,
  owner_user_id uuid,
  due_at timestamptz,
  done_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.activity_links (
  org_id uuid not null,
  activity_id uuid not null references public.activities (id) on delete cascade,
  subject_type text not null,
  subject_id text not null
);
`;

const OWN_TABLES = {
  "public.activities": "app.sql",
  "public.activity_links": "app.sql",
};

const BLOCKS: AnyBlocksConfig = {
  activities: {
    tables: {
      engagements: "public.activities",
      links: "public.activity_links",
    },
    columns: {
      engagements: {
        tenant: "org_id",
        type: "kind",
        durationSeconds: null,
        externalRef: null,
        createdBy: null,
        updatedAt: null,
      },
      links: { tenant: "org_id", engagement: "activity_id", position: null },
    },
  },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(
    ["memberships", "permissions", "subjects", "activities"],
    { modules: BLOCKS, ownTables: OWN_TABLES },
  );

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

describe("activities over the app's tables", BOOT, () => {
  it("logs, edits, completes and lists engagements in an enum type column", async () => {
    await expect(
      run(`do $$
declare
  v_row jsonb;
  v_id uuid;
begin
  ${SERVICE}
  v_row := better_supabase.log_engagement('${TENANT}', '{"type": "call", "title": "Intro", "dueAt": "2099-01-01T10:00:00Z", "durationSeconds": 60}'::jsonb, '[]'::jsonb);
  v_id := (v_row ->> 'id')::uuid;
  if v_row ->> 'kind' <> 'call' or v_row -> 'duration_seconds' <> 'null'::jsonb then
    raise exception 'logged %', v_row;
  end if;
  v_row := better_supabase.update_engagement(v_id, '{"type": "meeting", "outcome": "booked"}'::jsonb, null);
  if (select kind from public.activities where id = v_id) <> 'meeting' or v_row ->> 'outcome' <> 'booked' then
    raise exception 'updated %', v_row;
  end if;
  v_row := better_supabase.complete_engagement(v_id, true, 'done');
  if (select done_at from public.activities where id = v_id) is null then
    raise exception 'completed %', v_row;
  end if;
  if jsonb_array_length(better_supabase.open_engagements('${TENANT}', null, null, 50)) <> 0 then
    raise exception 'still open';
  end if;
  if not better_supabase.delete_engagement(v_id) then
    raise exception 'delete';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
