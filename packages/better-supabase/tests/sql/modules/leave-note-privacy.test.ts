import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ALICE = "22222222-2222-4222-8222-222222222222";
const BOB = "33333333-3333-4333-8333-333333333333";
const CAROL = "66666666-6666-4666-8666-666666666666";
const DAVE = "77777777-7777-4777-8777-777777777777";
const ALICE_EMPLOYEE = "44444444-4444-4444-8444-444444444444";
const BOB_EMPLOYEE = "55555555-5555-4555-8555-555555555555";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

// Every member reads all leave; only Carol approves and manages. Bob manages
// Alice in the employees block, and Dave is a colleague.
const ALLOW = `
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$
  select (permission not like '%.approve' and permission not like '%.manage') or auth.uid() = '${CAROL}'::uuid
$$;
create or replace function better_supabase.can_user(member uuid, scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$
  select (permission not like '%.approve' and permission not like '%.manage') or member = '${CAROL}'::uuid
$$;
create or replace function better_supabase.tenant_ids_with(permission text)
returns setof uuid language sql stable as $$ select '${TENANT}'::uuid $$;
insert into auth.users (id) values ('${ALICE}'), ('${BOB}'), ('${CAROL}'), ('${DAVE}') on conflict do nothing;
insert into better_supabase.memberships (organization_id, user_id, role)
  select '${TENANT}', u, 'member' from unnest(array['${ALICE}', '${BOB}', '${CAROL}', '${DAVE}']::uuid[]) u
  on conflict do nothing;
insert into better_supabase.employees (id, tenant_id, user_id, name, manager_id) values
  ('${BOB_EMPLOYEE}', '${TENANT}', '${BOB}', 'Bob', null),
  ('${ALICE_EMPLOYEE}', '${TENANT}', '${ALICE}', 'Alice', '${BOB_EMPLOYEE}');
`;

const as = (user: string): string =>
  `perform set_config('request.jwt.claims', '{"sub":"${user}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${user}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);`;

const BOOT = { timeout: 180_000 };

async function run(blocks: AnyBlocksConfig, check: string): Promise<void> {
  const files = renderBlocks(["employees", "leave"], { modules: blocks });

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      ...files
        .filter((file) => file.kind === "schema")
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

// Alice asks for leave with a private note; each reader then lists everyone's
// requests and reads hers by id.
const CHECK = (everyone: string): string => `do $$
declare
  v_type uuid;
  v_id uuid;
  v_note text;
begin
  ${as(CAROL)}
  v_type := (better_supabase.save_leave_type('${TENANT}', 'holiday', 'Holiday', 'days', true, false) ->> 'id')::uuid;
  ${as(ALICE)}
  v_id := (better_supabase.request_leave('${TENANT}', v_type, '2099-03-02', '2099-03-03', note => 'dentist') ->> 'id')::uuid;
  if better_supabase.list_leave_requests('${TENANT}') -> 0 ->> 'note' is distinct from 'dentist' then
    raise exception 'Alice lost her own note without everyone';
  end if;

  ${as(DAVE)}
  if jsonb_array_length(better_supabase.list_leave_requests('${TENANT}')) <> 0 then
    raise exception 'Dave saw leave without everyone';
  end if;

  ${everyone}
end;
$$;`;

const READERS = `
  ${as(DAVE)}
  if better_supabase.list_leave_requests('${TENANT}', everyone => true) -> 0 ->> 'note' is not null then
    raise exception 'a colleague read the note in list_leave_requests';
  end if;
  if better_supabase.get_leave_request(v_id) ->> 'note' is not null then
    raise exception 'a colleague read the note in get_leave_request';
  end if;
  if better_supabase.page_leave_requests('${TENANT}', '{"everyone": "true"}') -> 'items' -> 0 ->> 'note' is not null then
    raise exception 'a colleague read the note in page_leave_requests';
  end if;
  if jsonb_array_length(better_supabase.page_leave_requests('${TENANT}', '{"everyone": "true", "search": "dentist"}') -> 'items') <> 0 then
    raise exception 'a colleague found the request by its note';
  end if;

  foreach v_note in array array['${ALICE}', '${BOB}', '${CAROL}'] loop
    perform set_config('request.jwt.claims', json_build_object('sub', v_note, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_note, true);
    if better_supabase.list_leave_requests('${TENANT}', everyone => true) -> 0 ->> 'note' is distinct from 'dentist'
      or better_supabase.get_leave_request(v_id) ->> 'note' is distinct from 'dentist' then
      raise exception '% could not read the note', v_note;
    end if;
  end loop;`;

describe("leave request notes", BOOT, () => {
  it("shows an employee's note to them, their manager and deciders only", async () => {
    await expect(
      run(
        { leave: { options: { owner: "employee", approvals: false } } },
        CHECK(READERS),
      ),
    ).resolves.toBeUndefined();
  });

  it("finds the manager through the employees block for user-owned leave", async () => {
    await expect(
      run({ leave: { options: { approvals: false } } }, CHECK(READERS)),
    ).resolves.toBeUndefined();
  });

  it("still returns the note when the app revokes the column from authenticated", async () => {
    await expect(
      run(
        { leave: { options: { approvals: false } } },
        CHECK(`
  revoke select on better_supabase.leave_requests from authenticated;
  grant select (id, user_id) on better_supabase.leave_requests to authenticated;
  ${as(ALICE)}
  set local role authenticated;
  begin
    perform note from better_supabase.leave_requests;
    raise exception 'read the revoked note column';
  exception when insufficient_privilege then
    null;
  end;
  if better_supabase.get_leave_request(v_id) ->> 'note' is distinct from 'dentist' then
    raise exception 'get_leave_request lost the note under the column revoke';
  end if;
  reset role;`),
      ),
    ).resolves.toBeUndefined();
  });
});

describe("leave grants under expose", () => {
  const sqlOf = (grants: readonly string[]): string =>
    renderBlocks(["leave"], {
      grants: grants.map((table) => ({
        table,
        role: "authenticated",
        privileges: ["select"],
      })),
    })
      .filter((file) => file.module === "leave")
      .map((file) => file.contents)
      .join("\n");

  it("adds no select grant of its own to a table expose lists", () => {
    const grant =
      'grant select on "better_supabase"."leave_requests" to authenticated;';

    expect(sqlOf([])).toContain(grant);
    expect(sqlOf(["better_supabase.leave_requests"])).not.toContain(grant);
    expect(sqlOf(["better_supabase.leave_requests"])).not.toContain(
      'revoke all on "better_supabase"."leave_requests"',
    );
    expect(sqlOf(["better_supabase.leave_requests"])).toContain(
      'grant select on "better_supabase"."leave_types" to authenticated;',
    );
  });
});
