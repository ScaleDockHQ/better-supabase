import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { withBlockSubjects } from "../../../src/config/block-subjects.ts";
import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const USER = "22222222-2222-4222-8222-222222222222";
const ADA = "33333333-3333-4333-8333-333333333333";
const BOB = "44444444-4444-4444-8444-444444444444";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

const APP = `
create type public.employment_kind as enum ('full_time', 'part_time', 'contract');
create type public.applicant_source as enum ('referral', 'website');
create type public.applicant_phase as enum ('active', 'hired', 'rejected', 'withdrawn');
create type public.interview_format as enum ('phone', 'online', 'onsite');

create table public.candidates (
  id uuid primary key,
  tenant_id uuid not null
);

create table public.postings (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  title text not null,
  kind public.employment_kind,
  status text not null default 'draft',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.job_stages (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.postings (id) on delete cascade,
  name text not null,
  position integer not null,
  is_hired boolean not null default false,
  system_key text
);

create table public.applicants (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  posting_id uuid not null references public.postings (id) on delete cascade,
  candidate_id uuid not null references public.candidates (id),
  source public.applicant_source,
  stage_id uuid references public.job_stages (id),
  stage_entered_at timestamptz,
  phase public.applicant_phase not null default 'active',
  rank text collate "C" not null default 'V',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (posting_id, candidate_id)
);

create table public.applicant_reviews (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  applicant_id uuid not null references public.applicants (id) on delete cascade,
  reviewer_id uuid not null,
  score smallint not null,
  submitted_at timestamptz not null default now(),
  unique (applicant_id, reviewer_id)
);

create table public.review_scores (
  review_id uuid not null references public.applicant_reviews (id) on delete cascade,
  criterion text not null,
  value smallint not null check (value between 1 and 5),
  primary key (review_id, criterion)
);

create table public.applicant_interviews (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  applicant_id uuid not null references public.applicants (id) on delete cascade,
  kind public.interview_format,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  created_at timestamptz not null default now()
);

create table public.interview_panel (
  interview_id uuid not null references public.applicant_interviews (id) on delete cascade,
  user_id uuid not null,
  primary key (interview_id, user_id)
);
`;

const OWN_TABLES = {
  "public.postings": "app.sql",
  "public.applicants": "app.sql",
  "public.applicant_reviews": "app.sql",
  "public.applicant_interviews": "app.sql",
  "public.interview_panel": "app.sql",
  "public.review_scores": "app.sql",
};

const BLOCKS: AnyBlocksConfig = {
  hiring: {
    options: {
      candidate: "candidate",
      stages: {
        table: "public.job_stages",
        job: "job_id",
        rank: "position",
        hired: "is_hired",
        rejected: { column: "system_key", value: "rejected" },
      },
      scorecardKey: "application",
    },
    tables: {
      jobs: "public.postings",
      applications: "public.applicants",
      scorecards: "public.applicant_reviews",
      interviews: "public.applicant_interviews",
      interviewers: "public.interview_panel",
      scorecardScores: "public.review_scores",
    },
    columns: {
      jobs: {
        tenant: "org_id",
        employmentType: "kind",
        team: null,
        location: null,
        description: null,
        hiringManager: null,
        openedAt: null,
        closedAt: null,
      },
      applications: {
        tenant: "org_id",
        job: "posting_id",
        candidateType: null,
        state: "phase",
        owner: null,
        pipeline: null,
        rejectionReason: null,
        hiredAt: null,
      },
      scorecards: {
        tenant: "org_id",
        application: "applicant_id",
        reviewer: "reviewer_id",
        rating: "score",
        recommendation: null,
        stage: null,
        notes: null,
      },
      interviews: {
        tenant: "org_id",
        application: "applicant_id",
        interviewers: null,
        location: null,
        createdBy: null,
      },
      interviewers: { tenant: null },
      scorecardScores: {
        scorecard: "review_id",
        score: "value",
        criterion: "criterion",
        tenant: null,
        notes: null,
      },
    },
    values: {
      jobs: { employmentType: {} },
      applications: { source: {} },
      interviews: { kind: { video: "online" } },
    },
  },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role","sub":"${USER}"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);
  perform set_config('request.jwt.claim.sub', '${USER}', true);`;

const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const blocks = [
    "memberships",
    "permissions",
    "subjects",
    "pipelines",
    "hiring",
  ];

  const files = renderBlocks(blocks, {
    modules: BLOCKS,
    ownTables: OWN_TABLES,
    subjects: withBlockSubjects(
      {
        candidate: { table: "candidates", tenant: "tenant_id", idType: "uuid" },
      },
      blocks,
      BLOCKS,
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
      `insert into public.candidates (id, tenant_id) values ('${ADA}', '${TENANT}'), ('${BOB}', '${TENANT}');`,
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

const OPEN_JOB = `v_job := (better_supabase.save_job('${TENANT}', null, '{"title": "Engineer", "status": "open", "employmentType": "full_time"}'::jsonb) ->> 'id')::uuid;
  insert into public.job_stages (job_id, name, position, is_hired, system_key) values
    (v_job, 'Applied', 1, false, null),
    (v_job, 'Interview', 2, false, null),
    (v_job, 'Hired', 3, true, null),
    (v_job, 'Rejected', 4, false, 'rejected');`;

describe(
  "hiring over an app's typed candidates and per-job stages",
  BOOT,
  () => {
    it("runs applications through the job's own stages, panel and criterion scores", async () => {
      await expect(
        run(`do $$
declare
  v_job uuid;
  v_app uuid;
  v_second uuid;
  v_result jsonb;
  v_detail jsonb;
begin
  ${SERVICE}
  ${OPEN_JOB}
  if (select kind from public.postings where id = v_job) <> 'full_time' then
    raise exception 'kind %', (select kind from public.postings where id = v_job);
  end if;
  v_result := better_supabase.apply_to_job(v_job, '{"id": "${ADA}"}'::jsonb, 'referral', null);
  v_app := (v_result ->> 'id')::uuid;
  if v_result ->> 'candidate_type' <> 'candidate' or v_result ->> 'candidate_id' <> '${ADA}' or v_result ->> 'source' <> 'referral' then
    raise exception 'application %', v_result;
  end if;
  if (select s.name from public.applicants x join public.job_stages s on s.id = x.stage_id where x.id = v_app) <> 'Applied'
    or (select stage_entered_at from public.applicants where id = v_app) is null then
    raise exception 'stage %', (select to_jsonb(x) from public.applicants x where id = v_app);
  end if;
  if (better_supabase.apply_to_job(v_job, '{"type": "candidate", "id": "${ADA}"}'::jsonb, null, null) ->> 'id')::uuid <> v_app then
    raise exception 'applying again made a second application';
  end if;
  update public.applicants set stage_id = (select id from public.job_stages where job_id = v_job and name = 'Interview') where id = v_app;
  v_result := better_supabase.schedule_interview(v_app, now() + interval '1 hour', now() + interval '2 hours', array['${USER}']::uuid[], 'video', null);
  if (select kind from public.applicant_interviews where id = (v_result ->> 'id')::uuid) <> 'online'
    or v_result -> 'interviewer_user_ids' <> '["${USER}"]'::jsonb
    or (select count(*) from public.interview_panel) <> 1 then
    raise exception 'interview %', v_result;
  end if;
  perform better_supabase.submit_scorecard(v_app, 3, null, null, '[{"criterion": "craft", "score": 3}, {"criterion": "communication", "score": 2}]'::jsonb);
  v_result := better_supabase.submit_scorecard(v_app, 4, null, null, '[{"criterion": "craft", "score": 5}]'::jsonb);
  if (select count(*) from public.applicant_reviews where applicant_id = v_app) <> 1
    or (select count(*) from public.review_scores) <> 1
    or v_result -> 'scores' <> '[{"criterion": "craft", "score": 5, "notes": null}]'::jsonb then
    raise exception 'scorecard %', v_result;
  end if;
  v_detail := better_supabase.application_detail(v_app);
  if jsonb_array_length(v_detail -> 'scorecards') <> 1
    or v_detail -> 'scorecards' -> 0 -> 'scores' -> 0 ->> 'criterion' <> 'craft'
    or v_detail -> 'interviews' -> 0 -> 'interviewer_user_ids' <> '["${USER}"]'::jsonb
    or v_detail ->> 'candidate_type' <> 'candidate'
    or (v_detail ->> 'averageRating')::numeric <> 4 then
    raise exception 'detail %', v_detail;
  end if;
  v_result := better_supabase.close_application(v_app, 'hired', null);
  if v_result ->> 'phase' <> 'hired'
    or (select s.name from public.applicants x join public.job_stages s on s.id = x.stage_id where x.id = v_app) <> 'Hired' then
    raise exception 'hired %', v_result;
  end if;
  v_second := (better_supabase.apply_to_job(v_job, '{"id": "${BOB}"}'::jsonb, null, null) ->> 'id')::uuid;
  perform better_supabase.close_application(v_second, 'rejected', null);
  if (select phase from public.applicants where id = v_second) <> 'rejected'
    or (select s.system_key from public.applicants x join public.job_stages s on s.id = x.stage_id where x.id = v_second) <> 'rejected' then
    raise exception 'rejected %', (select to_jsonb(x) from public.applicants x where id = v_second);
  end if;
  update public.applicants set stage_id = (select id from public.job_stages where job_id = v_job and name = 'Interview') where id = v_second;
  if (select phase from public.applicants where id = v_second) <> 'active' then
    raise exception 'reopened %', (select to_jsonb(x) from public.applicants x where id = v_second);
  end if;
  perform better_supabase.close_application(v_second, 'withdrawn', null);
  if (select phase from public.applicants where id = v_second) <> 'withdrawn' then
    raise exception 'withdrawn %', (select to_jsonb(x) from public.applicants x where id = v_second);
  end if;
end;
$$;`),
      ).resolves.toBeUndefined();
    });

    it("refuses a candidate of another type", async () => {
      await expect(
        run(`do $$
declare
  v_job uuid;
begin
  ${SERVICE}
  ${OPEN_JOB}
  perform better_supabase.apply_to_job(v_job, '{"type": "person", "id": "${ADA}"}'::jsonb, null, null);
end;
$$;`),
      ).rejects.toThrow(/candidates of type candidate only/);
    });

    it("refuses a move to another job's stage", async () => {
      await expect(
        run(`do $$
declare
  v_job uuid;
  v_other uuid;
  v_app uuid;
begin
  ${SERVICE}
  ${OPEN_JOB}
  v_other := (better_supabase.save_job('${TENANT}', null, '{"title": "Designer", "status": "open"}'::jsonb) ->> 'id')::uuid;
  insert into public.job_stages (job_id, name, position) values (v_other, 'Applied', 1);
  v_app := (better_supabase.apply_to_job(v_job, '{"id": "${ADA}"}'::jsonb, null, null) ->> 'id')::uuid;
  update public.applicants set stage_id = (select id from public.job_stages where job_id = v_other) where id = v_app;
end;
$$;`),
      ).rejects.toThrow(/not an active stage of this application's job/);
    });

    it("refuses a score the app's column rejects", async () => {
      await expect(
        run(`do $$
declare
  v_job uuid;
  v_app uuid;
begin
  ${SERVICE}
  ${OPEN_JOB}
  v_app := (better_supabase.apply_to_job(v_job, '{"id": "${ADA}"}'::jsonb, null, null) ->> 'id')::uuid;
  perform better_supabase.submit_scorecard(v_app, 3, null, null, '[{"criterion": "craft", "score": 9}]'::jsonb);
end;
$$;`),
      ).rejects.toThrow(/distinct criterion and a valid score/);
    });
  },
);

const MANAGED: AnyBlocksConfig = {
  hiring: {
    options: { scorecardKey: "application", hiringManager: "employee" },
    tables: {
      interviewers: "interview_interviewers",
      scorecardScores: "application_scorecard_scores",
    },
    columns: {
      applications: { candidateType: null },
      scorecards: { recommendation: null },
      interviews: { interviewers: null },
    },
  },
};

const managedFiles = (modules: AnyBlocksConfig = MANAGED) => {
  const blocks = [
    "memberships",
    "permissions",
    "subjects",
    "pipelines",
    "hiring",
  ];

  return renderBlocks(blocks, {
    modules,
    subjects: withBlockSubjects(
      { person: { table: "people", tenant: "tenant_id", idType: "uuid" } },
      blocks,
      modules,
    ),
  });
};

const moduleSql = (
  files: ReturnType<typeof renderBlocks>,
  module: string,
): string =>
  files
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

describe("hiring's managed tables in the new modes", BOOT, () => {
  it("renders typed candidates, the junction, the scores table and the five-argument scorecard", () => {
    const sql = moduleSql(managedFiles(), "hiring");

    expect(sql).not.toContain('"candidate_type"');
    expect(sql).toContain('"candidate_id" uuid not null');
    expect(sql).toContain('unique ("job_id", "candidate_id")');
    expect(sql).toContain('unique ("application_id", "reviewer_user_id")');
    expect(sql).not.toContain('"recommendation" text');
    expect(sql).toContain(
      'create table if not exists "better_supabase"."interview_interviewers"',
    );
    expect(sql).toContain(
      'drop function if exists "better_supabase"."submit_scorecard"(uuid, integer, text, text);',
    );
    expect(sql).toContain("notes text, scores jsonb default null)");
    expect(sql).toContain(
      "better_supabase.as_column_type(save_job.attrs ->> 'hiringManagerId'",
    );
  });

  it("checks an employee hiring manager against the employees table", () => {
    const sql = moduleSql(
      renderBlocks(["hiring", "employees"], {
        modules: { hiring: { options: { hiringManager: "employee" } } },
      }),
      "hiring",
    );

    expect(sql).toContain(
      `select 1 from "better_supabase"."employees" x
    where x."id"::text = save_job.attrs ->> 'hiringManagerId'`,
    );
    expect(sql).toContain("HIRING_HIRING_MANAGER_INVALID");
  });

  it("contributes no pipeline binding when stages live per job", () => {
    const files = managedFiles({
      hiring: {
        options: {
          stages: {
            table: "public.job_stages",
            job: "job_id",
            rank: "position",
          },
        },
        columns: { applications: { pipeline: null } },
      },
    });

    expect(moduleSql(files, "pipelines")).not.toContain(
      "bsb_pipeline_application",
    );
    expect(moduleSql(files, "hiring")).toContain(
      'on "better_supabase"."applications" ("job_id", "stage_id", "rank")',
    );
  });

  it("refuses an unknown scorecard key", () => {
    expect(() =>
      managedFiles({ hiring: { options: { scorecardKey: "reviewer" } } }),
    ).toThrow(/must be "stage" or "application"/);
  });

  it("closes an application by state alone without a pipeline column", () => {
    const files = managedFiles({
      hiring: { columns: { applications: { pipeline: null } } },
    });

    const sql = moduleSql(files, "hiring");

    expect(moduleSql(files, "pipelines")).not.toContain(
      "bsb_pipeline_application",
    );
    expect(sql).toContain(
      `update "better_supabase"."applications" x set "state" = 'hired'`,
    );
    expect(sql).not.toContain("HIRING_STAGE_MISSING");
  });

  it("installs and runs them on a pipeline per job", async () => {
    const files = managedFiles();

    await using stack = await liteStack({
      driver: "pglite",
      migrations: [
        ROLES,
        "create table public.people (id uuid primary key, tenant_id uuid not null);",
        ...files
          .filter((file) => file.kind !== "data")
          .map((file) => file.contents),
      ],
      seed: [
        ...files
          .filter((file) => file.kind === "data")
          .map((file) => file.contents),
        `insert into public.people (id, tenant_id) values ('${ADA}', '${TENANT}');`,
        `do $$
declare
  v_job uuid;
  v_app uuid;
  v_result jsonb;
begin
  ${SERVICE}
  v_job := (better_supabase.save_job('${TENANT}', null, '{"title": "Engineer", "status": "open", "hiringManagerId": "${BOB}"}'::jsonb) ->> 'id')::uuid;
  v_result := better_supabase.apply_to_job(v_job, '{"id": "${ADA}"}'::jsonb, null, null);
  v_app := (v_result ->> 'id')::uuid;
  if v_result ->> 'candidate_type' <> 'person' then
    raise exception 'application %', v_result;
  end if;
  perform better_supabase.schedule_interview(v_app, now() + interval '1 hour', now() + interval '2 hours', array['${USER}']::uuid[], null, null);
  perform better_supabase.submit_scorecard(v_app, 3, null, 'Fine', '[{"criterion": "craft", "score": 3}]'::jsonb);
  v_result := better_supabase.application_detail(v_app);
  if v_result -> 'interviews' -> 0 -> 'interviewer_user_ids' <> '["${USER}"]'::jsonb
    or jsonb_array_length(v_result -> 'scorecards' -> 0 -> 'scores') <> 1 then
    raise exception 'detail %', v_result;
  end if;
  v_result := better_supabase.close_application(v_app, 'hired', null);
  if v_result ->> 'state' <> 'hired' then
    raise exception 'hired %', v_result;
  end if;
end;
$$;`,
      ],
    });

    expect(stack.url).not.toBe("");
  });
});
