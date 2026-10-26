import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { withBlockSubjects } from "../../../src/config/block-subjects.ts";
import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const USER = "22222222-2222-4222-8222-222222222222";
const PERSON = "33333333-3333-4333-8333-333333333333";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

// The app's own hiring tables: renamed columns, enum states, and no team,
// location, description, source, owner, reason, notes or interview kind
// columns. The module adds the pipeline, stage and rank columns.
const APP = `
create type public.opening_state as enum ('draft', 'open', 'closed');
create type public.candidacy_phase as enum ('active', 'hired', 'rejected', 'withdrawn');
create type public.review_verdict as enum ('strong_no', 'no', 'yes', 'strong_yes');
create type public.employment_kind as enum ('employee', 'contractor', 'freelance');

create table public.people (
  id uuid primary key,
  tenant_id uuid not null
);

create table public.openings (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  headline text not null,
  state public.opening_state not null default 'draft',
  employment_kind public.employment_kind,
  opened_on timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.candidacies (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  opening_id uuid not null references public.openings (id) on delete cascade,
  person_type text not null,
  person_id text not null,
  phase public.candidacy_phase not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  candidacy_id uuid not null references public.candidacies (id) on delete cascade,
  stage_id uuid,
  reviewer_id uuid not null,
  score smallint not null,
  verdict public.review_verdict not null,
  submitted_at timestamptz not null default now()
);

create table public.candidate_interviews (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  candidacy_id uuid not null references public.candidacies (id) on delete cascade,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  panel uuid[] not null default '{}',
  created_at timestamptz not null default now()
);
`;

const OWN_TABLES = {
  "public.openings": "app.sql",
  "public.candidacies": "app.sql",
  "public.reviews": "app.sql",
  "public.candidate_interviews": "app.sql",
};

const BLOCKS: AnyBlocksConfig = {
  hiring: {
    tables: {
      jobs: "public.openings",
      applications: "public.candidacies",
      scorecards: "public.reviews",
      interviews: "public.candidate_interviews",
    },
    columns: {
      jobs: {
        tenant: "org_id",
        title: "headline",
        status: "state",
        openedAt: "opened_on",
        team: null,
        location: null,
        employmentType: null,
        description: null,
        hiringManager: null,
        closedAt: null,
      },
      applications: {
        tenant: "org_id",
        job: "opening_id",
        candidateType: "person_type",
        candidateId: "person_id",
        state: "phase",
        source: null,
        owner: null,
        stageEnteredAt: null,
        rejectionReason: null,
        hiredAt: null,
      },
      scorecards: {
        tenant: "org_id",
        application: "candidacy_id",
        reviewer: "reviewer_id",
        rating: "score",
        recommendation: "verdict",
        notes: null,
      },
      interviews: {
        tenant: "org_id",
        application: "candidacy_id",
        interviewers: "panel",
        kind: null,
        location: null,
        createdBy: null,
      },
    },
  },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role","sub":"${USER}"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);
  perform set_config('request.jwt.claim.sub', '${USER}', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(
  check: string,
  modules: AnyBlocksConfig = BLOCKS,
  extra: readonly string[] = [],
): Promise<void> {
  const blocks = [
    "memberships",
    "permissions",
    "subjects",
    "pipelines",
    "hiring",
    ...extra,
  ];

  const files = renderBlocks(blocks, {
    modules,
    ownTables: OWN_TABLES,
    // Pipelines binds applications with a tenant_id tenant unless the app
    // registers the subject with its own column.
    subjects: withBlockSubjects(
      {
        person: { table: "people", tenant: "tenant_id" },
        application: { table: "candidacies", tenant: "org_id" },
      },
      blocks,
      modules,
    ),
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
      `insert into public.people (id, tenant_id) values ('${PERSON}', '${TENANT}');`,
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("hiring over the app's tables", BOOT, () => {
  it("opens a job, reviews and rejects an application in enum state columns", async () => {
    await expect(
      run(`do $$
declare
  v_job uuid;
  v_app uuid;
  v_detail jsonb;
begin
  ${SERVICE}
  v_job := (better_supabase.save_job('${TENANT}', null, '{"title": "Engineer", "status": "open"}'::jsonb) ->> 'id')::uuid;
  if (select state from public.openings where id = v_job) <> 'open'
    or (select opened_on from public.openings where id = v_job) is null then
    raise exception 'job %', (select to_jsonb(o) from public.openings o where id = v_job);
  end if;
  v_app := (better_supabase.apply_to_job(v_job, '{"id": "${PERSON}"}'::jsonb, null, null) ->> 'id')::uuid;
  perform better_supabase.submit_scorecard(v_app, 3, 'yes', null);
  perform better_supabase.submit_scorecard(v_app, 4, 'strong_yes', null);
  perform better_supabase.schedule_interview(v_app, now() + interval '1 hour', now() + interval '2 hours', array['${USER}']::uuid[], null, null);
  perform better_supabase.close_application(v_app, 'rejected', null);
  if (select phase from public.candidacies where id = v_app) <> 'rejected' then
    raise exception 'phase is %', (select phase from public.candidacies where id = v_app);
  end if;
  v_detail := better_supabase.application_detail(v_app);
  if jsonb_array_length(v_detail -> 'scorecards') <> 1 or jsonb_array_length(v_detail -> 'interviews') <> 1
    or v_detail -> 'scorecards' -> 0 ->> 'verdict' <> 'strong_yes' then
    raise exception 'detail %', v_detail;
  end if;
  perform better_supabase.save_job('${TENANT}', v_job, '{"status": "closed"}'::jsonb);
  if (select state from public.openings where id = v_job) <> 'closed' then
    raise exception 'job state is %', (select state from public.openings where id = v_job);
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("refuses a source the app's table has no column for", async () => {
    await expect(
      run(`do $$
declare
  v_job uuid;
begin
  ${SERVICE}
  v_job := (better_supabase.save_job('${TENANT}', null, '{"title": "Engineer", "status": "open"}'::jsonb) ->> 'id')::uuid;
  perform better_supabase.apply_to_job(v_job, '{"id": "${PERSON}"}'::jsonb, 'referral', null);
end;
$$;`),
    ).rejects.toThrow(/no source column/);
  });

  it("turns a hired application into an employee with the job's enum employment type", async () => {
    const hiring = BLOCKS["hiring"]!;

    const modules: AnyBlocksConfig = {
      ...BLOCKS,
      hiring: {
        ...hiring,
        columns: {
          ...hiring.columns,
          jobs: {
            ...hiring.columns!["jobs"],
            employmentType: "employment_kind",
          },
        },
        values: { jobs: { employmentType: { contractor: "freelance" } } },
      },
      employees: { options: { employmentTypes: ["employee", "contractor"] } },
    };

    await expect(
      run(
        `do $$
declare
  v_job uuid;
  v_app uuid;
  v_employee jsonb;
begin
  ${SERVICE}
  v_job := (better_supabase.save_job('${TENANT}', null, '{"title": "Engineer", "status": "open", "employmentType": "contractor"}'::jsonb) ->> 'id')::uuid;
  if (select employment_kind::text from public.openings where id = v_job) <> 'freelance' then
    raise exception 'job %', (select to_jsonb(o) from public.openings o where id = v_job);
  end if;
  v_app := (better_supabase.apply_to_job(v_job, '{"id": "${PERSON}"}'::jsonb, null, null) ->> 'id')::uuid;
  perform better_supabase.close_application(v_app, 'hired', null);
  v_employee := better_supabase.employee_from_application(v_app, '{"name": "Ada"}'::jsonb);
  if v_employee ->> 'employmentType' <> 'contractor' then
    raise exception 'employee %', v_employee;
  end if;
end;
$$;`,
        modules,
        ["employees"],
      ),
    ).resolves.toBeUndefined();
  });
});
