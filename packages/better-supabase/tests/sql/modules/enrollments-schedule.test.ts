import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const OWNER = "22222222-2222-4222-8222-222222222222";
const MEMBER = "33333333-3333-4333-8333-333333333333";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

const PEOPLE = `
insert into auth.users (id) values ('${OWNER}'), ('${MEMBER}');
insert into better_supabase.memberships (organization_id, user_id, role)
values ('${TENANT}', '${OWNER}', 'owner'), ('${TENANT}', '${MEMBER}', 'member');
`;

const as = (user: string): string =>
  `perform set_config('request.jwt.claims', '{"role":"authenticated","sub":"${user}"}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', '${user}', true);`;

const PROGRAM = JSON.stringify({
  key: "go-live",
  name: "Go live",
  steps: [
    {
      id: "kickoff",
      assignee: { userId: MEMBER },
      due: { days: 2, from: "start" },
    },
    { id: "import" },
    {
      id: "review",
      assignee: { role: "admin" },
      due: { days: -1, from: "end" },
    },
  ],
});

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["memberships", "permissions", "enrollments"], {});

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
      PEOPLE,
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("enrollment step schedules", BOOT, () => {
  it("renders due dates, lists open steps and lets the assignee complete theirs", async () => {
    await expect(
      run(`do $$
declare
  v_row jsonb;
  v_id uuid;
begin
  ${as(OWNER)}
  v_row := better_supabase.save_enrollment_program('${TENANT}', '${PROGRAM}'::jsonb);
  if v_row -> 'steps' -> 0 -> 'assignee' ->> 'userId' <> '${MEMBER}' or v_row -> 'steps' -> 1 ? 'due' then
    raise exception 'program %', v_row;
  end if;
  v_row := better_supabase.enroll('${TENANT}', 'go-live', 'contact', 'c1');
  v_id := (v_row ->> 'id')::uuid;
  if jsonb_array_length(v_row -> 'schedule') <> 2 or v_row -> 'schedule' -> 1 ? 'dueAt'
    or (v_row -> 'schedule' -> 0 ->> 'dueAt')::timestamptz <> (v_row ->> 'enrolledAt')::timestamptz + interval '2 days' then
    raise exception 'enrolled %', v_row;
  end if;
  v_row := better_supabase.set_enrollment_dates(v_id, '{"startsAt": "2026-11-01T00:00:00Z", "endsAt": "2026-11-30T00:00:00Z"}'::jsonb);
  if (v_row -> 'schedule' -> 0 ->> 'dueAt')::timestamptz <> '2026-11-03T00:00:00Z'
    or (v_row -> 'schedule' -> 1 ->> 'dueAt')::timestamptz <> '2026-11-29T00:00:00Z'
    or (v_row ->> 'completedSteps')::integer <> 0 or v_row ->> 'status' <> 'active' then
    raise exception 'dated %', v_row;
  end if;
  v_row := better_supabase.set_enrollment_dates(v_id, '{"endsAt": null}'::jsonb);
  if v_row -> 'endsAt' <> 'null'::jsonb or v_row -> 'schedule' -> 1 ? 'dueAt' or v_row ->> 'startsAt' is null then
    raise exception 'cleared %', v_row;
  end if;
  begin
    perform better_supabase.set_enrollment_dates(v_id, '{"startsAt": "soon"}'::jsonb);
    raise exception 'took a bad date';
  exception when sqlstate '22023' then null;
  end;
  if jsonb_array_length(better_supabase.open_enrollment_steps('${TENANT}', assignee_role => 'admin')) <> 1
    or jsonb_array_length(better_supabase.open_enrollment_steps('${TENANT}', due_before => '2026-11-10T00:00:00Z')) <> 1 then
    raise exception 'filters %', better_supabase.open_enrollment_steps('${TENANT}');
  end if;

  ${as(MEMBER)}
  v_row := better_supabase.open_enrollment_steps('${TENANT}', assignee_user => '${MEMBER}');
  if jsonb_array_length(v_row) <> 1 or v_row -> 0 ->> 'step' <> 'kickoff' or v_row -> 0 ->> 'id' <> v_id::text then
    raise exception 'assigned %', v_row;
  end if;
  v_row := better_supabase.complete_enrollment_step(v_id, 'kickoff');
  if (v_row ->> 'completedSteps')::integer <> 1 or v_row -> 'schedule' -> 0 ->> 'completedAt' is null then
    raise exception 'completed %', v_row;
  end if;
  begin
    perform better_supabase.complete_enrollment_step(v_id, 'review');
    raise exception 'completed a step assigned to a role';
  exception when sqlstate '42501' then null;
  end;

  ${as(OWNER)}
  v_row := better_supabase.reset_enrollment_step(v_id, 'kickoff');
  if (v_row ->> 'completedSteps')::integer <> 0 or v_row -> 'schedule' -> 0 ? 'completedAt'
    or (v_row -> 'schedule' -> 0 ->> 'dueAt')::timestamptz <> '2026-11-03T00:00:00Z' then
    raise exception 'reset %', v_row;
  end if;
  v_row := better_supabase.complete_enrollment_step(v_id, 'import');
  v_row := better_supabase.complete_enrollment_step(v_id, 'kickoff');
  v_row := better_supabase.complete_enrollment_step(v_id, 'review');
  if v_row ->> 'status' <> 'completed' or (v_row ->> 'completedSteps')::integer <> 3 then
    raise exception 'finished %', v_row;
  end if;
  if better_supabase.open_enrollment_steps('${TENANT}') <> '[]'::jsonb then
    raise exception 'still open';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("drops the schedule of a step that loses it when the subject enrolls again", async () => {
    await expect(
      run(`do $$
declare
  v_id uuid;
  v_row jsonb;
begin
  ${as(OWNER)}
  perform better_supabase.save_enrollment_program('${TENANT}', '${PROGRAM}'::jsonb);
  v_id := (better_supabase.enroll('${TENANT}', 'go-live', 'contact', 'c1') ->> 'id')::uuid;
  perform better_supabase.complete_enrollment_step(v_id, 'review');
  perform better_supabase.save_enrollment_program('${TENANT}', jsonb_build_object(
    'id', (select id from better_supabase.enrollment_programs where key = 'go-live'),
    'steps', '[{"id": "kickoff"}, {"id": "import"}, {"id": "review"}]'::jsonb
  ));
  v_row := better_supabase.enroll('${TENANT}', 'go-live', 'contact', 'c1');
  if v_row -> 'schedule' <> '[]'::jsonb or (v_row ->> 'completedSteps')::integer <> 1
    or (select count(*) from better_supabase.enrollment_steps where enrollment_id = v_id) <> 1 then
    raise exception 'unscheduled %', v_row;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("refuses an invalid assignee", async () => {
    await expect(
      run(`do $$
begin
  ${as(OWNER)}
  perform better_supabase.save_enrollment_program('${TENANT}', '{"key": "bad", "name": "Bad", "steps": [{"id": "a", "assignee": {"role": "admin", "userId": "${MEMBER}"}}]}'::jsonb);
end;
$$;`),
    ).rejects.toThrow(/a step assignee is/);
  });
});
