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

// PGlite has no pgcrypto; versions hashes snapshots with extensions.digest.
const PGCRYPTO = `
create schema if not exists extensions;
create or replace function extensions.digest(data text, kind text) returns bytea
language sql immutable as $$
  select sha256(convert_to(data, 'UTF8'))
$$;
`;

// The app's own care plans: renamed columns and no creator column.
const APP = `
create table public.support_plans (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  client_type text not null,
  client_id text not null,
  name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
`;

const OWN_TABLES = { "public.support_plans": "app.sql" };

const BLOCKS: AnyBlocksConfig = {
  "care-plans": {
    tables: { plans: "public.support_plans" },
    columns: {
      plans: {
        tenant: "org_id",
        subjectType: "client_type",
        subjectId: "client_id",
        title: "name",
        createdBy: null,
      },
    },
  },
};

const BASE = [
  "memberships",
  "permissions",
  "subjects",
  "versions",
  "care-plans",
];

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 120_000 };

async function run(
  check: string,
  layout: Parameters<typeof renderBlocks>[1] = {},
  app = "",
  modules: readonly string[] = BASE,
): Promise<void> {
  const files = renderBlocks(modules, layout);

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      PGCRYPTO,
      app,
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

/**
 * Builds a draft for client c-1 with one problem, goal, intervention and
 * measure.
 */
const DRAFT = `
  v_plan := better_supabase.create_care_plan('${TENANT}', '{"subjectType": "client", "subjectId": "c-1", "title": "Support plan"}'::jsonb);
  v_id := (v_plan ->> 'id')::uuid;
  if v_plan ->> 'status' <> 'draft' or (v_plan ->> 'version')::int <> 1 then
    raise exception 'created %', v_plan;
  end if;
  v_problem := (better_supabase.add_care_plan_problem(v_id, '{"code": "R45.1", "title": "Restless at night"}'::jsonb) ->> 'id')::uuid;
  v_goal := (better_supabase.add_care_plan_goal(v_problem, '{"title": "Sleeps through", "measure": {"nights": 5}}'::jsonb) ->> 'id')::uuid;
  v_action := better_supabase.add_care_plan_action(v_goal, '{"kind": "task", "title": "Evening routine", "reviewEvery": "P1M"}'::jsonb);
  if v_action ->> 'reviewEvery' <> 'P0Y1M0DT0H0M0S' or (v_action ->> 'requiresApproval')::boolean then
    raise exception 'action %', v_action;
  end if;
  v_measure := (better_supabase.add_care_plan_action(v_goal, '{"kind": "measure", "measureKind": "sensor", "title": "Door sensor"}'::jsonb) ->> 'id')::uuid;`;

const DECLARE = `declare
  v_plan jsonb;
  v_id uuid;
  v_next uuid;
  v_problem uuid;
  v_goal uuid;
  v_action jsonb;
  v_measure uuid;
  v_row jsonb;`;

const LIFECYCLE = `do $$
${DECLARE}
begin
  ${SERVICE}
  ${DRAFT}
  v_plan := better_supabase.publish_care_plan(v_id);
  if v_plan ->> 'status' <> 'active' or v_plan ->> 'publishedVersionId' is null
    or v_plan -> 'problems' -> 0 -> 'goals' -> 0 -> 'actions' -> 0 ->> 'status' <> 'active'
    or v_plan -> 'problems' -> 0 -> 'goals' -> 0 -> 'actions' -> 1 ->> 'status' <> 'planned' then
    raise exception 'published %', v_plan;
  end if;
  v_row := better_supabase.start_care_plan_action(v_measure);
  if v_row ->> 'status' <> 'active' then
    raise exception 'measure %', v_row;
  end if;
  if jsonb_array_length(better_supabase.list_care_plan_measures('${TENANT}')) <> 1 then
    raise exception 'measures %', better_supabase.list_care_plan_measures('${TENANT}');
  end if;
  v_row := better_supabase.record_care_plan_evaluation(v_goal, 'in_progress', 'Better on weekdays');
  v_plan := better_supabase.get_care_plan(v_id);
  if v_plan -> 'problems' -> 0 -> 'goals' -> 0 ->> 'status' <> 'in_progress'
    or jsonb_array_length(v_plan -> 'evaluations') <> 1 then
    raise exception 'evaluated %', v_plan;
  end if;
  perform better_supabase.review_care_plan_action((v_plan -> 'problems' -> 0 -> 'goals' -> 0 -> 'actions' -> 0 ->> 'id')::uuid, 'Fine');
  v_next := (better_supabase.create_care_plan('${TENANT}', jsonb_build_object('subjectType', 'client', 'subjectId', 'c-1', 'title', 'Support plan', 'copyFromPlanId', v_id, 'reviewOn', current_date)) ->> 'id')::uuid;
  v_plan := better_supabase.publish_care_plan(v_next);
  if (v_plan ->> 'version')::int <> 2 or jsonb_array_length(v_plan -> 'problems' -> 0 -> 'goals' -> 0 -> 'actions') <> 2 then
    raise exception 'copied %', v_plan;
  end if;
  v_plan := better_supabase.get_care_plan(v_id);
  if v_plan ->> 'status' <> 'archived'
    or v_plan -> 'problems' -> 0 -> 'goals' -> 0 -> 'actions' -> 1 ->> 'endReason' <> 'superseded' then
    raise exception 'superseded %', v_plan;
  end if;
  if jsonb_array_length(better_supabase.list_care_plans('client', 'c-1', true)) <> 2
    or jsonb_array_length(better_supabase.list_care_plans('client', 'c-1')) <> 1 then
    raise exception 'list %', better_supabase.list_care_plans('client', 'c-1', true);
  end if;
  if better_supabase.due_care_plan_reviews() <> 1 or better_supabase.due_care_plan_reviews() <> 0 then
    raise exception 'reviews';
  end if;
  v_plan := better_supabase.archive_care_plan(v_next);
  if v_plan ->> 'status' <> 'archived' then
    raise exception 'archived %', v_plan;
  end if;
end;
$$;`;

describe("care-plans over the app's table", BOOT, () => {
  it("drafts, publishes, evaluates, supersedes and archives a plan", async () => {
    await expect(run(LIFECYCLE)).resolves.toBeUndefined();
  });

  it("runs the same lifecycle in the app's renamed columns", async () => {
    await expect(
      run(LIFECYCLE, { modules: BLOCKS, ownTables: OWN_TABLES }, APP),
    ).resolves.toBeUndefined();
  });

  it("needs a problem to publish and refuses edits once published", async () => {
    await expect(
      run(`do $$
declare
  v_id uuid;
begin
  ${SERVICE}
  v_id := (better_supabase.create_care_plan('${TENANT}', '{"subjectType": "client", "subjectId": "c-1", "title": "A"}'::jsonb) ->> 'id')::uuid;
  perform better_supabase.publish_care_plan(v_id);
end;
$$;`),
    ).rejects.toThrow(/needs a problem/);

    await expect(
      run(`do $$
${DECLARE}
begin
  ${SERVICE}
  ${DRAFT}
  perform better_supabase.publish_care_plan(v_id);
  perform better_supabase.update_care_plan_goal(v_goal, '{"title": "Other"}'::jsonb);
end;
$$;`),
    ).rejects.toThrow(/draft/);
  });

  it("checks the code system, the measure kind and the review interval", async () => {
    const layout = {
      modules: {
        "care-plans": {
          options: { codeSystems: ["icd-10"], measureKinds: ["sensor"] },
        },
      },
    };

    await expect(
      run(
        `do $$
${DECLARE}
begin
  ${SERVICE}
  ${DRAFT}
  if v_plan -> 'problems' is null then
    raise exception 'tree';
  end if;
  perform better_supabase.add_care_plan_problem(v_id, '{"codeSystem": "snomed", "title": "B"}'::jsonb);
end;
$$;`,
        layout,
      ),
    ).rejects.toThrow(/code system/);

    await expect(
      run(
        `do $$
${DECLARE}
begin
  ${SERVICE}
  ${DRAFT}
  perform better_supabase.add_care_plan_action(v_goal, '{"kind": "measure", "measureKind": "seclusion", "title": "B"}'::jsonb);
end;
$$;`,
        layout,
      ),
    ).rejects.toThrow(/measureKind/);

    await expect(
      run(`do $$
${DECLARE}
begin
  ${SERVICE}
  ${DRAFT}
  perform better_supabase.add_care_plan_action(v_goal, '{"title": "B", "reviewEvery": "-1 day"}'::jsonb);
end;
$$;`),
    ).rejects.toThrow(/positive interval/);
  });

  it("asks approvals before a measure starts and creates the task's work item", async () => {
    await expect(
      run(
        `do $$
${DECLARE}
begin
  ${SERVICE}
  ${DRAFT}
  v_plan := better_supabase.publish_care_plan(v_id);
  v_action := v_plan -> 'problems' -> 0 -> 'goals' -> 0 -> 'actions' -> 0;
  v_row := v_plan -> 'problems' -> 0 -> 'goals' -> 0 -> 'actions' -> 1;
  if v_action ->> 'taskId' is null or v_row ->> 'approvalId' is null or v_row ->> 'status' <> 'planned' then
    raise exception 'published %', v_plan;
  end if;
  begin
    perform better_supabase.start_care_plan_action(v_measure);
    raise exception 'started before the approval';
  exception when others then
    if sqlerrm not like '%waits for its approval%' then
      raise;
    end if;
  end;
  perform better_supabase.care_plan_action_approved(v_measure);
  if (better_supabase.get_care_plan(v_id) -> 'problems' -> 0 -> 'goals' -> 0 -> 'actions' -> 1 ->> 'status') <> 'active' then
    raise exception 'approved';
  end if;
end;
$$;`,
        {},
        "",
        [...BASE, "approvals", "tasks", "signatures", "notifications"],
      ),
    ).resolves.toBeUndefined();
  });
});
