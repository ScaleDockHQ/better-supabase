import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ANNA = "22222222-2222-4222-8222-222222222222";
const BOB = "33333333-3333-4333-8333-333333333333";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

// The app's own queues and members: an enum strategy, no territory, rank or
// assigned count columns. The module adds the columns it is missing.
const APP = `
create type public.routing_strategy as enum ('round_robin', 'weighted');

create table public.routing_queues (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  label text not null,
  subject_type text not null,
  strategy public.routing_strategy not null default 'round_robin',
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.routing_members (
  queue_id uuid not null references public.routing_queues (id) on delete cascade,
  org_id uuid not null,
  user_id uuid not null,
  weight integer not null default 1,
  active boolean not null default true,
  credit bigint not null default 0,
  last_assigned_at timestamptz
);
`;

const OWN_TABLES = {
  "public.routing_queues": "app.sql",
  "public.routing_members": "app.sql",
};

const BLOCKS: AnyBlocksConfig = {
  assignment: {
    tables: {
      queues: "public.routing_queues",
      members: "public.routing_members",
    },
    columns: {
      queues: { tenant: "org_id", name: "label", conditions: null, rank: null },
      members: { tenant: "org_id", assignedCount: null },
    },
  },
};

const OWNER = `perform set_config('request.jwt.claims', '{"role":"authenticated","sub":"${ANNA}"}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', '${ANNA}', true);`;

const PEOPLE = `
insert into auth.users (id) values ('${ANNA}'), ('${BOB}');
insert into better_supabase.memberships (organization_id, user_id, role)
values ('${TENANT}', '${ANNA}', 'owner'), ('${TENANT}', '${BOB}', 'member');
`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(
    ["memberships", "permissions", "subjects", "automations", "assignment"],
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

describe("assignment over the app's tables", BOOT, () => {
  it("rotates records through a queue with an enum strategy", async () => {
    await expect(
      run(`do $$
declare
  v_queue jsonb;
  v_id uuid;
  v_first jsonb;
  v_second jsonb;
begin
  ${OWNER}
  v_queue := better_supabase.save_assignment_queue('${TENANT}', '{"name": "Inbound", "subjectType": "lead", "strategy": "weighted"}'::jsonb);
  v_id := (v_queue ->> 'id')::uuid;
  if v_queue ->> 'strategy' <> 'weighted' or v_queue -> 'conditions' <> 'null'::jsonb or (v_queue ->> 'rank')::integer <> 0 then
    raise exception 'queue %', v_queue;
  end if;
  perform better_supabase.set_assignment_members(v_id, jsonb_build_array(
    jsonb_build_object('userId', '${ANNA}'), jsonb_build_object('userId', '${BOB}')
  ));
  perform better_supabase.set_assignment_members(v_id, jsonb_build_array(
    jsonb_build_object('userId', '${ANNA}', 'weight', 2), jsonb_build_object('userId', '${BOB}')
  ));
  if (select count(*) from public.routing_members where queue_id = v_id) <> 2 then
    raise exception 'members were duplicated';
  end if;
  perform better_supabase.save_assignment_queue('${TENANT}', jsonb_build_object('id', v_id, 'strategy', 'round_robin'));
  if (select strategy from public.routing_queues where id = v_id) <> 'round_robin' then
    raise exception 'strategy not changed';
  end if;
  v_first := better_supabase.assign_subject('${TENANT}', 'lead', 'l1');
  v_second := better_supabase.assign_subject('${TENANT}', 'lead', 'l2');
  if v_first ->> 'strategy' <> 'round_robin' or v_first ->> 'userId' = v_second ->> 'userId' then
    raise exception 'picks % %', v_first, v_second;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("refuses a territory the app's table has no column for", async () => {
    await expect(
      run(`do $$
begin
  ${OWNER}
  perform better_supabase.save_assignment_queue('${TENANT}', '{"name": "EU", "subjectType": "lead", "conditions": {"all": []}}'::jsonb);
end;
$$;`),
    ).rejects.toThrow(/no conditions column/);
  });
});
