import { describe, expect, it } from "vitest";

import { createHiring } from "../../../src/blocks/hiring/index.ts";

function transport(
  results: Record<string, (args: Record<string, unknown>) => unknown>,
) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    call(_schema: string, fn: string, args: Record<string, unknown>) {
      calls.push([fn, args]);
      const result = results[fn];

      if (!result) {
        return Promise.reject(new Error(`unexpected ${fn}`));
      }

      return Promise.resolve(result(args));
    },
  };
}

const APPLICATION = {
  id: "a1",
  tenant_id: "o",
  job_id: "j1",
  candidate_type: "person",
  candidate_id: "p1",
  source: "referral",
  owner_user_id: "u1",
  pipeline_id: "pl1",
  stage_id: "s1",
  stage_entered_at: "2026-10-15T09:00:00Z",
  state: "rejected",
  rejection_reason: "Late",
  hired_at: null,
  created_at: "2026-10-15T09:00:00Z",
};

describe("hiring block", () => {
  it("saves jobs and applies candidates", async () => {
    const t = transport({
      save_job: () => ({
        id: "j1",
        title: "Engineer",
        team_id: null,
        location: "Utrecht",
        employment_type: "full_time",
        description: null,
        hiring_manager_user_id: "u2",
        status: "open",
        opened_at: "2026-10-15T09:00:00Z",
        closed_at: null,
      }),
      apply_to_job: () => APPLICATION,
    });

    const hiring = createHiring({ transport: t });

    const job = await hiring
      .saveJob({
        organizationId: "o",
        job: { title: "Engineer", status: "open" },
      })
      .orThrow();

    expect(job).toMatchObject({
      status: "open",
      location: "Utrecht",
      hiringManagerId: "u2",
    });
    expect(job.openedAt).toBeDefined();

    const application = await hiring
      .apply({ jobId: "j1", candidate: { id: "p1" }, source: "referral" })
      .orThrow();

    expect(application).toMatchObject({
      candidate: { type: "person", id: "p1" },
      state: "rejected",
      rejectionReason: "Late",
    });
    expect(t.calls.map(([, args]) => args)).toEqual([
      { tenant: "o", job: null, attrs: { title: "Engineer", status: "open" } },
      { job: "j1", candidate: { id: "p1" }, source: "referral", owner: null },
    ]);
  });

  it("closes, scores, schedules and reads the detail", async () => {
    const card = {
      id: "c1",
      stage_id: "s1",
      reviewer_user_id: "u3",
      rating: 4,
      recommendation: "strong_yes",
      notes: null,
      submitted_at: "2026-10-16T09:00:00Z",
    };

    const interview = {
      id: "i1",
      kind: "technical",
      starts_at: "2026-10-20T09:00:00Z",
      ends_at: "2026-10-20T10:00:00Z",
      location: null,
      interviewer_user_ids: ["u3"],
    };

    const t = transport({
      close_application: () => ({
        ...APPLICATION,
        state: "hired",
        rejection_reason: null,
        hired_at: "2026-10-21T09:00:00Z",
      }),
      submit_scorecard: () => card,
      schedule_interview: () => interview,
      application_detail: () => ({
        ...APPLICATION,
        scorecards: [card],
        interviews: [interview],
        averageRating: "3.50",
      }),
    });

    const hiring = createHiring({ transport: t });
    expect((await hiring.hire("a1").orThrow()).hiredAt).toBeDefined();
    await hiring.reject({ applicationId: "a1", reason: "Late" }).orThrow();
    await hiring.withdraw("a1").orThrow();
    expect(
      (
        await hiring
          .score({
            applicationId: "a1",
            card: { rating: 4, recommendation: "strong_yes" },
          })
          .orThrow()
      ).rating,
    ).toBe(4);
    const start = Temporal.Instant.from("2026-10-20T09:00:00Z");
    expect(
      (
        await hiring
          .scheduleInterview({
            applicationId: "a1",
            interview: { startsAt: start, endsAt: start.add({ hours: 1 }) },
          })
          .orThrow()
      ).interviewerIds,
    ).toEqual(["u3"]);
    const detail = await hiring.detail("a1").orThrow();
    expect(detail).toMatchObject({
      averageRating: 3.5,
      scorecards: [{ recommendation: "strong_yes" }],
      interviews: [{ kind: "technical" }],
    });
    expect(t.calls.slice(0, 3).map(([, args]) => args)).toEqual([
      { application: "a1", outcome: "hired", reason: null },
      { application: "a1", outcome: "rejected", reason: "Late" },
      { application: "a1", outcome: "withdrawn", reason: null },
    ]);
    expect(t.calls[4]?.[1]).toEqual({
      application: "a1",
      starts_at: "2026-10-20T09:00:00Z",
      ends_at: "2026-10-20T10:00:00Z",
      interviewers: [],
      kind: null,
      location: null,
    });

    const empty = createHiring({
      transport: transport({
        application_detail: () => ({
          ...APPLICATION,
          scorecards: [],
          interviews: [],
          averageRating: null,
        }),
      }),
    });

    expect((await empty.detail("a1").orThrow()).averageRating).toBeUndefined();
  });
});
