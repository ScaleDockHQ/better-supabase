import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ADA = "22222222-2222-4222-8222-222222222222";
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

// The app's own rota: renamed tenant, time and member columns, and no
// location, note, creator, assigner or timestamps.
const APP = `
create table public.rota_shifts (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  template_id uuid,
  team_id uuid,
  begins_at timestamptz not null,
  finishes_at timestamptz not null,
  break_minutes integer not null default 0,
  headcount integer not null default 1,
  required_qualifications text[] not null default '{}',
  status text not null default 'draft',
  published_at timestamptz,
  canceled_at timestamptz
);

create table public.rota_assignments (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  shift_id uuid not null references public.rota_shifts (id) on delete cascade,
  member_id uuid not null,
  status text not null default 'assigned',
  begins_at timestamptz not null,
  finishes_at timestamptz not null
);
create index rota_assignments_shift_idx on public.rota_assignments (shift_id);
`;

const BLOCKS: AnyBlocksConfig = {
  shifts: {
    tables: {
      shifts: "public.rota_shifts",
      assignments: "public.rota_assignments",
    },
    columns: {
      shifts: {
        tenant: "org_id",
        startsAt: "begins_at",
        endsAt: "finishes_at",
        location: null,
        note: null,
        createdBy: null,
        createdAt: null,
        updatedAt: null,
      },
      assignments: {
        tenant: "org_id",
        user: "member_id",
        startsAt: "begins_at",
        endsAt: "finishes_at",
        assignedBy: null,
        createdAt: null,
        updatedAt: null,
      },
    },
  },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

/**
 * PGlite has no btree_gist; the app's assignments carry no exclusion
 * constraint.
 */
const withoutGist = (contents: string): string =>
  contents
    .replace(
      "create extension if not exists btree_gist with schema extensions;",
      "",
    )
    .replace(
      'create extension if not exists "btree_gist" with schema "extensions";',
      "",
    );

async function run(check: string): Promise<void> {
  const files = renderBlocks(["shifts"], {
    modules: BLOCKS,
    ownTables: {
      "public.rota_shifts": "app.sql",
      "public.rota_assignments": "app.sql",
    },
  });

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      APP,
      ...files
        .filter((file) => file.kind !== "data")
        .map((file) => withoutGist(file.contents)),
    ],
    seed: [
      ...files
        .filter((file) => file.kind === "data")
        .map((file) => withoutGist(file.contents)),
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("shifts over the app's rota tables", BOOT, () => {
  it("plans, publishes, assigns, refuses overlap and swaps", async () => {
    await expect(
      run(`do $$
declare
  v_first jsonb;
  v_second jsonb;
  v_assignment jsonb;
  v_swap jsonb;
  v_roster jsonb;
  v_failed boolean;
begin
  ${SERVICE}
  insert into auth.users (id, email) values ('${ADA}', 'ada@example.com'), ('${BOB}', 'bob@example.com');
  insert into better_supabase.memberships (organization_id, user_id, role)
    values ('${TENANT}', '${ADA}', 'member'), ('${TENANT}', '${BOB}', 'member');
  v_first := better_supabase.save_shift('${TENANT}', '2030-03-04T08:00:00Z', '2030-03-04T16:00:00Z', null, null, 30, 1);
  v_second := better_supabase.save_shift('${TENANT}', '2030-03-04T12:00:00Z', '2030-03-04T20:00:00Z');
  if (select count(*) from public.rota_shifts) <> 2 or (select break_minutes from public.rota_shifts where id = (v_first ->> 'id')::uuid) <> 30 then
    raise exception 'shifts %', v_first;
  end if;
  if better_supabase.publish_shifts('${TENANT}', '2030-03-04', '2030-03-04') <> 2 then
    raise exception 'publish';
  end if;
  v_assignment := better_supabase.assign_shift((v_first ->> 'id')::uuid, '${ADA}');
  if (select member_id from public.rota_assignments) <> '${ADA}'::uuid
    or (select begins_at from public.rota_assignments) <> '2030-03-04T08:00:00Z'::timestamptz then
    raise exception 'assignment %', v_assignment;
  end if;
  v_failed := false;
  begin
    perform better_supabase.assign_shift((v_second ->> 'id')::uuid, '${ADA}');
  exception when exclusion_violation then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'overlap was assigned';
  end if;
  v_swap := better_supabase.request_shift_swap((v_assignment ->> 'id')::uuid, '${BOB}');
  perform better_supabase.decide_shift_swap((v_swap ->> 'id')::uuid, true);
  if (select member_id from public.rota_assignments where status = 'assigned') <> '${BOB}'::uuid then
    raise exception 'swap %', v_swap;
  end if;
  v_roster := better_supabase.roster('${TENANT}', '2030-03-04', '2030-03-04');
  if jsonb_array_length(v_roster) <> 2 then
    raise exception 'roster %', v_roster;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
