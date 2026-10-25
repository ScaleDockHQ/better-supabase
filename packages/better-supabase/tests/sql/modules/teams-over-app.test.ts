import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ALICE = "22222222-2222-4222-8222-222222222222";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

// An app's teams table: a required icon column without a default and an enum
// status.
const APP = `
create type public.team_status as enum ('active', 'archived');

create table public.teams (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  name text not null,
  slug text not null,
  icon_name text not null,
  status public.team_status not null default 'active',
  description text,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.team_members (
  organization_id uuid not null,
  team_id uuid not null references public.teams (id) on delete cascade,
  user_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (team_id, user_id)
);
`;

const BLOCKS: AnyBlocksConfig = {
  teams: {
    tables: { teams: "public.teams", members: "public.team_members" },
    columns: {
      teams: { tenant: "organization_id" },
      members: { tenant: "organization_id" },
    },
    permissions: {
      create: "team.create",
      update: "team.update",
      delete: "team.delete",
      members: "team.update",
    },
    options: { extraColumns: { icon_name: "text not null" } },
  },
};

// The caller holds team.create only.
const ALLOW = `
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select permission in ('team.create', 'teams.read') $$;
create or replace function better_supabase.tenant_ids_with(permission text)
returns setof uuid language sql stable as $$ select '${TENANT}'::uuid $$;
`;

const AS_ALICE = `perform set_config('request.jwt.claims', '{"sub":"${ALICE}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${ALICE}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);`;

const AS_SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["teams"], {
    modules: BLOCKS,
    ownTables: { "public.teams": "app.sql", "public.team_members": "app.sql" },
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
      ALLOW,
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("teams over the app's tables", BOOT, () => {
  it("creates with a caller slug and a required extra column, splits the keys and restores", async () => {
    await expect(
      run(`do $$
declare
  v_team jsonb;
  v_hint text;
begin
  ${AS_ALICE}
  v_team := better_supabase.create_team('${TENANT}', 'Field ops', null, 'field', '{"icon_name": "truck"}');
  if v_team ->> 'slug' <> 'field' or (select icon_name from public.teams) <> 'truck' then
    raise exception 'create %', v_team;
  end if;
  begin
    perform better_supabase.archive_team((v_team ->> 'id')::uuid);
    v_hint := 'none';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
  end;
  if v_hint <> 'TEAM_FORBIDDEN' then
    raise exception 'archive without team.update: %', v_hint;
  end if;
  ${AS_SERVICE}
  perform better_supabase.update_team((v_team ->> 'id')::uuid, 'Field ops', 'Vans', null, '{"icon_name": "van"}');
  perform better_supabase.update_team((v_team ->> 'id')::uuid, 'Field ops', null, '{"description": null, "slug": "field-ops"}');
  if (select description from public.teams) is not null or (select slug from public.teams) <> 'field-ops' then
    raise exception 'patch %', (select jsonb_agg(t) from public.teams t);
  end if;
  perform better_supabase.archive_team((v_team ->> 'id')::uuid);
  perform better_supabase.restore_team((v_team ->> 'id')::uuid);
  if (select status::text from public.teams) <> 'active' then
    raise exception 'restore';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
