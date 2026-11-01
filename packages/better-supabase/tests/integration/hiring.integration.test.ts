import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";
import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { createContacts } from "../../src/blocks/contacts/index.ts";
import { createHiring } from "../../src/blocks/hiring/index.ts";
import { createPipelines } from "../../src/blocks/pipelines/index.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = [
  "organizations",
  "outbox",
  "subjects",
  "contacts",
  "pipelines",
  "hiring",
];

const layout: BlockSqlLayout = {
  subjects: {
    ...withBlockSubjects({}, ["contacts"], {}),
    application: {
      table: "better_supabase.applications",
      idType: "uuid",
      tenant: "tenant_id",
    },
  },
};

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

describe.skipIf(!live)("hiring", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("runs a candidate through a job's pipeline to a hire", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const interviewer = await s.user("interviewer");
      await s.install(MODULES, layout);
      const org = await s.organization(owner, { member: interviewer });
      const transport = sqlTransport(s.sql);
      const hiring = createHiring({ transport });

      await s.as(owner);

      const draft = await hiring
        .saveJob({
          organizationId: org,
          job: { title: "Backend engineer", location: "Utrecht" },
        })
        .orThrow();

      const ada = await createContacts({ transport })
        .savePerson({ organizationId: org, input: { name: "Ada" } })
        .orThrow();

      expect(
        hint(
          await hiring.apply({ jobId: draft.id, candidate: { id: ada.id } }),
        ),
      ).toBe("JOB_OPENING_NOT_OPEN");

      const job = await hiring
        .saveJob({ organizationId: org, job: { id: draft.id, status: "open" } })
        .orThrow();

      expect(job.openedAt).toBeDefined();

      const application = await hiring
        .apply({ jobId: job.id, candidate: { id: ada.id }, source: "referral" })
        .orThrow();

      expect(application).toMatchObject({
        candidate: { type: "person", id: ada.id },
        state: "active",
        source: "referral",
      });
      expect(
        (
          await hiring
            .apply({ jobId: job.id, candidate: { type: "person", id: ada.id } })
            .orThrow()
        ).id,
      ).toBe(application.id);
      expect(
        hint(
          await hiring.apply({
            jobId: job.id,
            candidate: { id: crypto.randomUUID() },
          }),
        ),
      ).toBe("HIRING_CANDIDATE_FORBIDDEN");

      const [pipeline] = await createPipelines({ transport })
        .list({ organizationId: org, subjectType: "application" })
        .orThrow();

      expect(pipeline?.scopeId).toBe(job.id);
      expect(pipeline?.stages.map((stage) => stage.key)).toEqual([
        "applied",
        "screening",
        "interview",
        "offer",
        "hired",
        "rejected",
        "withdrawn",
      ]);

      const start = Temporal.Instant.from("2026-10-20T09:00:00Z");

      const interview = await hiring
        .scheduleInterview({
          applicationId: application.id,
          interview: {
            startsAt: start,
            endsAt: start.add({ hours: 1 }),
            interviewerIds: [interviewer.id],
            kind: "technical",
          },
        })
        .orThrow();

      expect(interview.interviewerIds).toEqual([interviewer.id]);

      await s.as(interviewer);
      await hiring
        .score({
          applicationId: application.id,
          card: { rating: 3, recommendation: "yes", notes: "Solid" },
        })
        .orThrow();
      await hiring
        .score({
          applicationId: application.id,
          card: { rating: 4, recommendation: "strong_yes" },
        })
        .orThrow();
      expect(
        hint(
          await hiring.score({
            applicationId: application.id,
            card: { rating: 5, recommendation: "yes" },
          }),
        ),
      ).toBe("HIRING_SCORECARD_INVALID");
      expect(hint(await hiring.hire(application.id))).toBe(
        "HIRING_APPLICATION_NOT_FOUND",
      );

      await s.as(owner);
      await hiring
        .score({
          applicationId: application.id,
          card: { rating: 2, recommendation: "no" },
        })
        .orThrow();
      const detail = await hiring.detail(application.id).orThrow();
      expect(detail.scorecards).toHaveLength(2);
      expect(detail.averageRating).toBe(3);
      expect(detail.interviews).toHaveLength(1);

      const hired = await hiring.hire(application.id).orThrow();
      expect(hired.state).toBe("hired");
      expect(hired.hiredAt).toBeDefined();

      const events = await s.rows<{ type: string }>(
        "select type from better_supabase.outbox_events where organization_id = $1 and (type like 'application.%' or type like 'job_opening.%' or type like 'scorecard.%' or type like 'interview.%') order by created_at",
        [org],
      );

      expect(events.map((row) => row.type)).toEqual(
        expect.arrayContaining([
          "job_opening.opened",
          "application.created",
          "interview.scheduled",
          "scorecard.submitted",
          "application.hired",
        ]),
      );

      const bob = await createContacts({ transport })
        .savePerson({ organizationId: org, input: { name: "Bob" } })
        .orThrow();

      const second = await hiring
        .apply({ jobId: job.id, candidate: { id: bob.id } })
        .orThrow();

      const rejected = await hiring
        .reject({ applicationId: second.id, reason: "Not enough experience" })
        .orThrow();

      expect(rejected).toMatchObject({
        state: "rejected",
        rejectionReason: "Not enough experience",
      });

      const closed = await hiring
        .saveJob({ organizationId: org, job: { id: job.id, status: "closed" } })
        .orThrow();

      expect(closed.closedAt).toBeDefined();
      await s.as(interviewer);
      expect(
        hint(
          await hiring.saveJob({ organizationId: org, job: { title: "x" } }),
        ),
      ).toBe("HIRING_FORBIDDEN");
    } finally {
      await s.close();
    }
  });
});
