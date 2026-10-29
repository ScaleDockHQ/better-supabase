import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ALICE = "22222222-2222-4222-8222-222222222222";
const BOB = "33333333-3333-4333-8333-333333333333";
const CAROL = "44444444-4444-4444-8444-444444444444";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;

-- PGlite loads no pgcrypto here; invitation tokens need random bytes and sha256.
create schema if not exists extensions;
create function extensions.gen_random_bytes(n integer) returns bytea
language sql volatile as $$ select decode(md5(random()::text), 'hex') $$;
create function extensions.digest(data text, type text) returns bytea
language sql immutable as $$ select sha256(convert_to(data, 'UTF8')) $$;
`;

const BLOCKS: AnyBlocksConfig = {
  memberships: { options: { roles: { many: true } } },
};

const SEED = `
insert into auth.users (id) values ('${ALICE}'), ('${BOB}');
insert into auth.users (id, email, email_confirmed_at) values ('${CAROL}', 'carol@example.com', now());
insert into better_supabase.organizations (id, name, slug) values ('${TENANT}', 'Acme', 'acme');
insert into better_supabase.memberships (organization_id, user_id, role) values
  ('${TENANT}', '${ALICE}', 'owner'), ('${TENANT}', '${BOB}', 'member');
`;

const as = (user: string): string =>
  `perform set_config('request.jwt.claims', '{"sub":"${user}","role":"authenticated","tenant_id":"${TENANT}"}', true);
  perform set_config('request.jwt.claim.sub', '${user}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(
  check: string,
  blocks: readonly string[] = ["memberships", "permissions", "organizations"],
  modules: AnyBlocksConfig = {},
): Promise<void> {
  const files = renderBlocks(blocks, { modules: { ...BLOCKS, ...modules } });

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      ...files
        .filter((file) => file.kind !== "data")
        .map((file) => file.contents),
    ],
    seed: [
      ...files
        .filter((file) => file.kind === "data")
        .map((file) => file.contents),
      SEED,
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

const ROLE_SET = (user: string): string =>
  `(select array_agg("role" order by "role") from better_supabase.membership_roles where user_id = '${user}')`;

describe("memberships with many roles", BOOT, () => {
  it("keeps the role set and the primary role in step", async () => {
    await expect(
      run(`do $$
begin
  if ${ROLE_SET(BOB)} <> array['member'] then
    raise exception 'insert did not seed the set: %', ${ROLE_SET(BOB)};
  end if;
  insert into better_supabase.membership_roles (organization_id, user_id, "role") values ('${TENANT}', '${BOB}', 'admin');
  if (select "role" from better_supabase.memberships where user_id = '${BOB}') <> 'admin' then
    raise exception 'primary role did not follow the highest role';
  end if;
  if ${ROLE_SET(BOB)} <> array['admin', 'member'] then
    raise exception 'the primary sync replaced the set: %', ${ROLE_SET(BOB)};
  end if;
  perform set_config('request.jwt.claims', '{"sub":"${BOB}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${BOB}', true);
  if not better_supabase.has_organization_role('${TENANT}', array['member']) then
    raise exception 'a secondary role does not count';
  end if;
  if better_supabase.organization_member_roles('${TENANT}', '${BOB}') <> array['admin', 'member'] then
    raise exception 'organization_member_roles %', better_supabase.organization_member_roles('${TENANT}', '${BOB}');
  end if;
  update better_supabase.memberships set "role" = 'viewer' where user_id = '${BOB}';
  if ${ROLE_SET(BOB)} <> array['member', 'viewer'] then
    raise exception 'a direct role write did not swap only the old primary: %', ${ROLE_SET(BOB)};
  end if;
  if (select "role" from better_supabase.memberships where user_id = '${BOB}') <> 'viewer' then
    raise exception 'the written role did not stay primary';
  end if;
  delete from better_supabase.memberships where user_id = '${BOB}';
  if exists (select 1 from better_supabase.membership_roles where user_id = '${BOB}') then
    raise exception 'roles outlived the membership';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("adds and removes roles through the organizations functions", async () => {
    await expect(
      run(`do $$
begin
  ${as(ALICE)}
  if not better_supabase.add_member_role('${TENANT}', '${BOB}', 'admin') then
    raise exception 'add_member_role returned false';
  end if;
  if better_supabase.add_member_role('${TENANT}', '${BOB}', 'admin') then
    raise exception 'adding a held role reported a change';
  end if;
  if not better_supabase.remove_member_role('${TENANT}', '${BOB}', 'member') then
    raise exception 'remove_member_role returned false';
  end if;
  if ${ROLE_SET(BOB)} <> array['admin'] then
    raise exception 'set %', ${ROLE_SET(BOB)};
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("grants an invitation's extra roles and teams on accept", async () => {
    await expect(
      run(
        `do $$
declare
  v_invite jsonb;
  v_team uuid;
begin
  insert into better_supabase.teams (tenant_id, name, slug) values ('${TENANT}', 'Ops', 'ops') returning id into v_team;
  ${as(ALICE)}
  v_invite := better_supabase.invite_member('${TENANT}', 'carol@example.com', 'member', '7 days', '{}',
    jsonb_build_object('roles', array['admin'], 'teams', array[v_team]));
  perform set_config('request.jwt.claims', '{"sub":"${CAROL}","role":"authenticated","email":"carol@example.com"}', true);
  perform set_config('request.jwt.claim.sub', '${CAROL}', true);
  perform better_supabase.accept_invitation(v_invite ->> 'token');
  if ${ROLE_SET(CAROL)} <> array['admin', 'member'] then
    raise exception 'roles %', ${ROLE_SET(CAROL)};
  end if;
  if not exists (select 1 from better_supabase.team_members where team_id = v_team and user_id = '${CAROL}') then
    raise exception 'not in the team';
  end if;
end;
$$;`,
        ["memberships", "permissions", "organizations", "invitations", "teams"],
        {
          invitations: { options: { onAccept: { roles: true, teams: true } } },
        },
      ),
    ).resolves.toBeUndefined();
  });

  it("refuses an invitation role above the inviter's ceiling", async () => {
    await expect(
      run(
        `do $$
begin
  update better_supabase.memberships set "role" = 'admin' where user_id = '${ALICE}';
  ${as(ALICE)}
  perform better_supabase.invite_member('${TENANT}', 'carol@example.com', 'member', '7 days', '{}',
    jsonb_build_object('roles', array['owner']));
end;
$$;`,
        ["memberships", "permissions", "organizations", "invitations"],
        { invitations: { options: { onAccept: { roles: true } } } },
      ),
    ).rejects.toThrow(/on_accept.roles is above/);
  });

  it("refuses to remove a member's last role", async () => {
    await expect(
      run(`do $$
begin
  ${as(ALICE)}
  perform better_supabase.remove_member_role('${TENANT}', '${BOB}', 'member');
end;
$$;`),
    ).rejects.toThrow(/keeps at least one role/);
  });
});

const AUTH_ADMIN_READS = `
grant usage on schema better_supabase to supabase_auth_admin;
grant select on better_supabase.memberships to supabase_auth_admin;
create policy auth_admin_reads on better_supabase.memberships for select to supabase_auth_admin using (true);
do $$
declare
  v_count integer;
begin
  set local role supabase_auth_admin;
  select count(*) into v_count from better_supabase.memberships;
  reset role;
  perform set_config('test.auth_admin_rows', v_count::text, false);
end;
$$;`;

describe("tenantScope.exemptRoles", BOOT, () => {
  it("lets an exempt role read past the tenant scope", async () => {
    await expect(
      run(
        `${AUTH_ADMIN_READS}
do $$
begin
  if current_setting('test.auth_admin_rows') <> '2' then
    raise exception 'exempt role read % rows', current_setting('test.auth_admin_rows');
  end if;
end;
$$;`,
        ["memberships", "permissions", "organizations"],
        {
          memberships: {
            options: { roles: { many: true } },
            tenantScope: { exemptRoles: ["supabase_auth_admin"] },
          },
        },
      ),
    ).resolves.toBeUndefined();
  });

  it("keeps the scope for a role that is not exempt", async () => {
    await expect(run(AUTH_ADMIN_READS)).rejects.toThrow(
      /permission denied for function member_organization_ids/,
    );
  });
});
