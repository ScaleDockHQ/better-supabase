import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const OTHER = "99999999-9999-4999-8999-999999999999";
const ALICE = "22222222-2222-4222-8222-222222222222";
const BOB = "33333333-3333-4333-8333-333333333333";
const DAN = "44444444-4444-4444-8444-444444444444";
const ERIN = "55555555-5555-4555-8555-555555555555";
const ALICE_EMPLOYEE = "66666666-6666-4666-8666-666666666666";
const SALES = "77777777-7777-4777-8777-777777777777";
const OPS = "88888888-8888-4888-8888-888888888888";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

const ALLOW = `
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select true $$;
create or replace function better_supabase.tenant_ids_with(permission text)
returns setof uuid language sql stable as $$ select '${TENANT}'::uuid $$;
`;

// Alice and Bob are members; Dan is an employee without an account, Erin one
// of another organization. Alice's own row on sales predates her employee
// record, which is on ops; the sync trigger is off, as it was before the
// upgrade, so the data file has to fill both.
const BEFORE_UPGRADE = `
insert into auth.users (id) values ('${ALICE}'), ('${BOB}');
insert into better_supabase.memberships (organization_id, user_id, role) values
  ('${TENANT}', '${ALICE}', 'member'), ('${TENANT}', '${BOB}', 'member');
insert into better_supabase.teams (id, tenant_id, name, slug) values
  ('${SALES}', '${TENANT}', 'Sales', 'sales'), ('${OPS}', '${TENANT}', 'Ops', 'ops');
insert into better_supabase.team_members (team_id, user_id, tenant_id) values
  ('${SALES}', '${ALICE}', '${TENANT}'), ('${SALES}', '${BOB}', '${TENANT}');
alter table better_supabase.employees disable trigger bsb_employee_team_members;
insert into better_supabase.employees (id, tenant_id, user_id, name, team_id) values
  ('${ALICE_EMPLOYEE}', '${TENANT}', '${ALICE}', 'Alice', '${OPS}');
alter table better_supabase.employees enable trigger bsb_employee_team_members;
insert into better_supabase.employees (id, tenant_id, user_id, name) values
  ('${DAN}', '${TENANT}', null, 'Dan'), ('${ERIN}', '${OTHER}', null, 'Erin');
`;

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

const ROWS = (team: string): string =>
  `(select coalesce(jsonb_agg(jsonb_build_array(user_id, employee_id) order by employee_id nulls last, user_id), '[]')
    from better_supabase.team_members where team_id = '${team}')`;

const BOOT = { timeout: 120_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["teams", "employees", "outbox"], {});

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      ...files
        .filter((file) => file.kind === "schema")
        .map((file) => file.contents),
    ],
    seed: [
      BEFORE_UPGRADE,
      ...files
        .filter((file) => file.kind === "data")
        .map((file) => file.contents),
      ALLOW,
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("teams with employees", BOOT, () => {
  it("backfills, adds employees with or without an account and keeps them through account changes", async () => {
    await expect(
      run(`do $$
declare
  v_list jsonb;
  v_hint text;
begin
  ${SERVICE}
  if ${ROWS(SALES)} <> '[["${ALICE}", "${ALICE_EMPLOYEE}"], ["${BOB}", null]]'::jsonb
    or ${ROWS(OPS)} <> '[["${ALICE}", "${ALICE_EMPLOYEE}"]]'::jsonb then
    raise exception 'backfill % %', ${ROWS(SALES)}, ${ROWS(OPS)};
  end if;

  perform better_supabase.add_team_member('${OPS}', employee => '${DAN}');
  perform better_supabase.add_team_member('${OPS}', '${BOB}');
  if ${ROWS(OPS)} <> '[[null, "${DAN}"], ["${ALICE}", "${ALICE_EMPLOYEE}"], ["${BOB}", null]]'::jsonb then
    raise exception 'add %', ${ROWS(OPS)};
  end if;
  if (select payload from better_supabase.outbox_events where type = 'team_member.added' order by position limit 1)
    <> jsonb_build_object('organizationId', '${TENANT}', 'id', '${OPS}', 'userId', null, 'employeeId', '${DAN}') then
    raise exception 'event %', (select jsonb_agg(payload) from better_supabase.outbox_events);
  end if;

  v_list := (select x from jsonb_array_elements(better_supabase.list_teams('${TENANT}')) x where x ->> 'id' = '${OPS}');
  if jsonb_array_length(v_list -> 'member_ids') <> 2
    or not v_list -> 'member_ids' @> '["${ALICE}", "${BOB}"]'::jsonb
    or jsonb_array_length(v_list -> 'member_employee_ids') <> 2
    or not v_list -> 'member_employee_ids' @> '["${ALICE_EMPLOYEE}", "${DAN}"]'::jsonb then
    raise exception 'list %', v_list;
  end if;

  -- Bob's account is linked to Dan's record: the two rows become one.
  update better_supabase.employees set user_id = '${BOB}' where id = '${DAN}';
  if ${ROWS(OPS)} <> '[["${BOB}", "${DAN}"], ["${ALICE}", "${ALICE_EMPLOYEE}"]]'::jsonb
    or ${ROWS(SALES)} <> '[["${BOB}", "${DAN}"], ["${ALICE}", "${ALICE_EMPLOYEE}"]]'::jsonb then
    raise exception 'link % %', ${ROWS(OPS)}, ${ROWS(SALES)};
  end if;
  if not ('${OPS}'::uuid in (select better_supabase.team_ids_of('${BOB}'))) then
    raise exception 'team_ids_of';
  end if;

  update better_supabase.employees set user_id = null where id = '${DAN}';
  if ${ROWS(OPS)} <> '[[null, "${DAN}"], ["${ALICE}", "${ALICE_EMPLOYEE}"]]'::jsonb then
    raise exception 'unlink %', ${ROWS(OPS)};
  end if;

  update better_supabase.employees set user_id = '${BOB}' where id = '${DAN}';
  delete from better_supabase.memberships where user_id = '${BOB}';
  if ${ROWS(OPS)} <> '[[null, "${DAN}"], ["${ALICE}", "${ALICE_EMPLOYEE}"]]'::jsonb then
    raise exception 'membership delete %', ${ROWS(OPS)};
  end if;

  delete from auth.users where id = '${ALICE}';
  if ${ROWS(SALES)} <> '[[null, "${DAN}"], [null, "${ALICE_EMPLOYEE}"]]'::jsonb
    or (select user_id from better_supabase.employees where id = '${ALICE_EMPLOYEE}') is not null then
    raise exception 'auth user delete %', ${ROWS(SALES)};
  end if;

  perform better_supabase.remove_team_member('${SALES}', employee => '${DAN}');
  update better_supabase.employees set team_id = '${SALES}' where id = '${DAN}';
  update better_supabase.employees set team_id = '${SALES}' where id = '${ERIN}';
  if ${ROWS(SALES)} <> '[[null, "${DAN}"], [null, "${ALICE_EMPLOYEE}"]]'::jsonb then
    raise exception 'primary team %', ${ROWS(SALES)};
  end if;

  delete from better_supabase.employees where id = '${DAN}';
  if exists (select 1 from better_supabase.team_members where employee_id = '${DAN}') then
    raise exception 'employee delete';
  end if;

  begin
    perform better_supabase.add_team_member('${OPS}', employee => '${ERIN}');
    v_hint := 'none';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
  end;
  if v_hint <> 'TEAM_MEMBER_INVALID' then
    raise exception 'employee of another tenant: %', v_hint;
  end if;
  begin
    perform better_supabase.add_team_member('${OPS}', '${BOB}', '${ALICE_EMPLOYEE}');
    v_hint := 'none';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
  end;
  if v_hint <> 'TEAM_MEMBER_INVALID' then
    raise exception 'user and employee: %', v_hint;
  end if;

  if not better_supabase.remove_team_member('${OPS}', employee => '${ALICE_EMPLOYEE}')
    or better_supabase.remove_team_member('${OPS}', employee => '${ALICE_EMPLOYEE}') then
    raise exception 'remove';
  end if;
  if (select payload from better_supabase.outbox_events where type = 'team_member.deleted' order by position desc limit 1)
    <> jsonb_build_object('organizationId', '${TENANT}', 'id', '${OPS}', 'userId', null, 'employeeId', '${ALICE_EMPLOYEE}') then
    raise exception 'deleted event';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("keeps user-only rows cascading with the membership", async () => {
    await expect(
      run(`do $$
begin
  delete from better_supabase.memberships where user_id = '${BOB}';
  if exists (select 1 from better_supabase.team_members where user_id = '${BOB}') then
    raise exception 'user-only row stayed';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});

describe("teams without employees", () => {
  it("renders the user-only table and functions", () => {
    const sql = renderBlocks(["teams"], {})
      .map((file) => file.contents)
      .join("\n");

    expect(sql).not.toContain("employee_id");
    expect(sql).toContain('primary key ("team_id", "user_id")');
  });

  it("leaves employees out when columns.members.employee is null", () => {
    const sql = renderBlocks(["teams", "employees"], {
      modules: { teams: { columns: { members: { employee: null } } } },
    })
      .filter((file) => file.module === "teams")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).not.toContain("employee_id");
  });
});
