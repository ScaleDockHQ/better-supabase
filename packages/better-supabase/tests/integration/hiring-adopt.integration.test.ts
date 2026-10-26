import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../src/config/blocks.ts";
import type { Result } from "../../src/core/result.ts";

import { createHiring } from "../../src/blocks/hiring/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const APP = `
create type public.bsb_test_employment as enum ('full_time', 'part_time');
create type public.bsb_test_phase as enum ('active', 'hired', 'rejected', 'withdrawn');
create type public.bsb_test_format as enum ('phone', 'online');

create table public.bsb_test_candidates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null
);

create table public.bsb_test_jobs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  title text not null,
  employment_type public.bsb_test_employment,
  status text not null default 'draft',
  opened_at timestamptz,
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.bsb_test_job_stages (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.bsb_test_jobs (id) on delete cascade,
  name text not null,
  position integer not null,
  is_hired boolean not null default false,
  system_key text
);

create table public.bsb_test_applications (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  job_id uuid not null references public.bsb_test_jobs (id) on delete cascade,
  candidate_id uuid not null references public.bsb_test_candidates (id),
  source text,
  stage_id uuid references public.bsb_test_job_stages (id),
  stage_entered_at timestamptz,
  state public.bsb_test_phase not null default 'active',
  rank text collate "C" not null default 'V',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (job_id, candidate_id)
);

create table public.bsb_test_scorecards (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  application_id uuid not null references public.bsb_test_applications (id) on delete cascade,
  reviewer_user_id uuid not null,
  rating smallint not null,
  submitted_at timestamptz not null default now(),
  unique (application_id, reviewer_user_id)
);

create table public.bsb_test_scorecard_scores (
  scorecard_id uuid not null references public.bsb_test_scorecards (id) on delete cascade,
  criterion text not null,
  score smallint not null check (score between 1 and 5),
  primary key (scorecard_id, criterion)
);

create table public.bsb_test_interviews (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  application_id uuid not null references public.bsb_test_applications (id) on delete cascade,
  kind public.bsb_test_format,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  created_at timestamptz not null default now()
);

create table public.bsb_test_interview_panel (
  interview_id uuid not null references public.bsb_test_interviews (id) on delete cascade,
  user_id uuid not null,
  primary key (interview_id, user_id)
);
`;

const TABLES = {
  jobs: "public.bsb_test_jobs",
  applications: "public.bsb_test_applications",
  scorecards: "public.bsb_test_scorecards",
  interviews: "public.bsb_test_interviews",
  interviewers: "public.bsb_test_interview_panel",
  scorecardScores: "public.bsb_test_scorecard_scores",
};

const MODULES: AnyBlocksConfig = {
  hiring: {
    options: {
      candidate: "candidate",
      stages: {
        table: "public.bsb_test_job_stages",
        job: "job_id",
        rank: "position",
        hired: "is_hired",
        rejected: { column: "system_key", value: "rejected" },
      },
      scorecardKey: "application",
    },
    tables: TABLES,
    columns: {
      jobs: {
        team: null,
        location: null,
        description: null,
        hiringManager: null,
      },
      applications: {
        candidateType: null,
        pipeline: null,
        owner: null,
        rejectionReason: null,
        hiredAt: null,
      },
      scorecards: { recommendation: null, stage: null, notes: null },
      interviews: { interviewers: null, location: null, createdBy: null },
      interviewers: { tenant: null },
      scorecardScores: { criterion: "criterion", tenant: null, notes: null },
    },
    values: {
      jobs: { employmentType: {} },
      interviews: { kind: { video: "online" } },
    },
  },
};

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

describe.skipIf(!live)("hiring over the app's tables", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("hires through a job's own stages with a panel and criterion scores", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.rows(APP);
      await s.install(["organizations", "subjects", "pipelines", "hiring"], {
        modules: MODULES,
        ownTables: Object.fromEntries(
          Object.values(TABLES).map((table) => [table, "app.sql"]),
        ),
        subjects: {
          candidate: {
            table: "bsb_test_candidates",
            tenant: "tenant_id",
            idType: "uuid",
          },
        },
      });

      await s.rows(
        `alter table public.bsb_test_candidates enable row level security;
         grant select on public.bsb_test_candidates to authenticated;
         create policy "read" on public.bsb_test_candidates for select to authenticated
           using (better_supabase.has_organization_role(tenant_id));`,
      );
      const owner = await s.user("owner");
      const interviewer = await s.user("interviewer");
      const org = await s.organization(owner, { member: interviewer });
      const hiring = createHiring({ transport: sqlTransport(s.sql) });

      const [ada, bob] = await s.rows<{ id: string }>(
        "insert into public.bsb_test_candidates (tenant_id) values ($1), ($1) returning id",
        [org],
      );

      await s.as(owner);

      const job = await hiring
        .saveJob(org, {
          title: "Backend engineer",
          status: "open",
          employmentType: "full_time",
        })
        .orThrow();

      const stages = await s.rows<{ id: string; name: string }>(
        `insert into public.bsb_test_job_stages (job_id, name, position, is_hired, system_key) values
           ($1, 'Applied', 1, false, null), ($1, 'Interview', 2, false, null),
           ($1, 'Hired', 3, true, null), ($1, 'Rejected', 4, false, 'rejected')
         returning id, name`,
        [job.id],
      );

      const stage = (name: string): string =>
        stages.find((row) => row.name === name)?.id ?? "";

      const application = await hiring.apply(job.id, { id: ada!.id }).orThrow();

      expect(application).toMatchObject({
        candidate: { type: "candidate", id: ada!.id },
        stageId: stage("Applied"),
        state: "active",
      });
      expect(
        hint(await hiring.apply(job.id, { type: "person", id: ada!.id })),
      ).toBe("HIRING_CANDIDATE_TYPE_UNSUPPORTED");

      const start = Temporal.Instant.from("2026-10-20T09:00:00Z");

      const interview = await hiring
        .scheduleInterview(application.id, {
          startsAt: start,
          endsAt: start.add({ hours: 1 }),
          interviewerIds: [interviewer.id],
          kind: "video",
        })
        .orThrow();

      expect(interview.interviewerIds).toEqual([interviewer.id]);
      expect(
        await s.value<string>(
          "(select kind::text from public.bsb_test_interviews where id = $1)",
          [interview.id],
        ),
      ).toBe("online");

      await s.as(interviewer);
      await hiring
        .score(application.id, {
          rating: 3,
          scores: [
            { criterion: "craft", score: 3 },
            { criterion: "communication", score: 4 },
          ],
        })
        .orThrow();

      const card = await hiring
        .score(application.id, {
          rating: 4,
          scores: [{ criterion: "craft", score: 5 }],
        })
        .orThrow();

      expect(card.recommendation).toBeUndefined();
      expect(card.scores).toEqual([{ criterion: "craft", score: 5 }]);

      await s.as(owner);
      const detail = await hiring.detail(application.id).orThrow();
      expect(detail.scorecards).toHaveLength(1);
      expect(detail.scorecards[0]?.scores).toEqual([
        { criterion: "craft", score: 5 },
      ]);
      expect(detail.interviews[0]?.interviewerIds).toEqual([interviewer.id]);

      const hired = await hiring.hire(application.id).orThrow();
      expect(hired).toMatchObject({ state: "hired", stageId: stage("Hired") });

      const second = await hiring.apply(job.id, { id: bob!.id }).orThrow();
      const rejected = await hiring.reject(second.id).orThrow();
      expect(rejected).toMatchObject({
        state: "rejected",
        stageId: stage("Rejected"),
      });
    } finally {
      await s.close();
    }
  });
});
