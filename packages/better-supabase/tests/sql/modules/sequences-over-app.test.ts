import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const USER = "22222222-2222-4222-8222-222222222222";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

// The app's own sequences: an enum status and no description column. Runs
// live on enrollments, which the module adds its run columns to.
const APP = `
create type public.cadence_state as enum ('draft', 'active', 'paused', 'archived');

create table public.cadences (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  key text not null,
  title text not null,
  state public.cadence_state not null default 'draft',
  exit_on_reply boolean not null default true,
  steps jsonb not null default '[]',
  version integer,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

`;

const OWN_TABLES = { "public.cadences": "app.sql" };

const BLOCKS: AnyBlocksConfig = {
  sequences: {
    tables: { sequences: "public.cadences" },
    columns: {
      sequences: {
        tenant: "org_id",
        name: "title",
        status: "state",
        description: null,
      },
    },
  },
};

const OWNER = `perform set_config('request.jwt.claims', '{"role":"authenticated","sub":"${USER}"}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', '${USER}', true);`;

const PEOPLE = `
insert into auth.users (id) values ('${USER}');
insert into better_supabase.memberships (organization_id, user_id, role)
values ('${TENANT}', '${USER}', 'owner');
`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(
    ["memberships", "permissions", "enrollments", "sequences"],
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
      PEOPLE,
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("sequences over the app's tables", BOOT, () => {
  it("enrolls, pauses and exits a recipient on enrollments", async () => {
    await expect(
      run(`do $$
declare
  v_sequence jsonb;
  v_id uuid;
  v_member jsonb;
  v_run uuid;
begin
  ${OWNER}
  v_sequence := better_supabase.save_sequence('${TENANT}', '{"key": "welcome", "name": "Welcome", "status": "active", "steps": [{"id": "pause", "kind": "wait", "minutes": 60}]}'::jsonb);
  v_id := (v_sequence ->> 'id')::uuid;
  if v_sequence ->> 'status' <> 'active' or (v_sequence ->> 'version')::integer <> 1 or v_sequence -> 'description' <> 'null'::jsonb then
    raise exception 'sequence %', v_sequence;
  end if;
  if jsonb_array_length(better_supabase.list_sequences('${TENANT}', 'active')) <> 1 then
    raise exception 'not listed';
  end if;
  v_member := better_supabase.enroll_in_sequence(v_id, 'contact', 'c1', '{"name": "Ada"}'::jsonb);
  v_run := (v_member ->> 'id')::uuid;
  if v_member ->> 'status' <> 'active'
    or (select program from better_supabase.enrollments where id = v_run) <> 'sequence:' || v_id
    or (select due_at from better_supabase.enrollment_steps where enrollment_id = v_run and completed_at is null) <= now() then
    raise exception 'enrolled %', v_member;
  end if;
  v_member := better_supabase.change_sequence_enrollment(v_run, 'pause');
  if v_member ->> 'status' <> 'paused' or (select paused_at from better_supabase.enrollments where id = v_run) is null then
    raise exception 'paused %', v_member;
  end if;
  v_member := better_supabase.change_sequence_enrollment(v_run, 'exit');
  if (select cancel_reason from better_supabase.enrollments where id = v_run) <> 'manual'
    or (select status from better_supabase.enrollments where id = v_run) <> 'cancelled'
    or v_member ->> 'status' <> 'exited' or v_member ->> 'exitReason' <> 'manual' then
    raise exception 'exited %', v_member;
  end if;
  perform better_supabase.enroll_in_sequence(v_id, 'contact', 'c1', '{"name": "Ada"}'::jsonb);
  if (select count(*) from better_supabase.enrollments where program = 'sequence:' || v_id) <> 1
    or (select status from better_supabase.enrollments where id = v_run) <> 'active'
    or (select cancel_reason from better_supabase.enrollments where id = v_run) is not null then
    raise exception 'restarted';
  end if;
  if jsonb_array_length(better_supabase.list_sequence_enrollments('${TENANT}', jsonb_build_object('status', 'active'))) <> 1 then
    raise exception 'not filtered';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("refuses a description the app's table has no column for", async () => {
    await expect(
      run(`do $$
begin
  ${OWNER}
  perform better_supabase.save_sequence('${TENANT}', '{"key": "intro", "name": "Intro", "description": "Hello"}'::jsonb);
end;
$$;`),
    ).rejects.toThrow(/no description column/);
  });
});
