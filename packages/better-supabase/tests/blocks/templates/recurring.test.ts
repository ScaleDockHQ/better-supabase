import * as v from "valibot";
import { describe, expect, it } from "vitest";

import type { TemplateJobs } from "../../../src/blocks/templates/index.ts";

import {
  createTemplates,
  defineTemplateType,
  TEMPLATE_RECUR_QUEUE,
  templatesBlock,
} from "../../../src/blocks/templates/index.ts";
import { planOccurrences } from "../../../src/blocks/templates/recurring.ts";
import { dbError } from "../../../src/core/errors.ts";
import { AsyncResult } from "../../../src/core/result.ts";

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

const AT = "2026-10-06T09:00:00Z";

const signal = new AbortController().signal;

const SCHEDULE = {
  id: "s1",
  template: "t1",
  tenant: "o",
  input: { owner: "u1" },
  enabled: true,
  dtstart: "2026-10-01T09:00:00Z",
  tzid: "UTC",
  rrule: "FREQ=DAILY",
  createdBy: "u1",
  createdAt: AT,
  updatedAt: AT,
};

const TEMPLATE = {
  id: "t1",
  tenant: "o",
  scope: "tenant",
  key: null,
  type: "invoice",
  name: "Monthly invoice",
  language: "en",
  isDefault: false,
  settings: {},
  forkedFrom: null,
  forkedFromVersion: null,
  publishedVersion: 1,
  upstreamVersion: null,
  createdBy: "u1",
  createdAt: AT,
  updatedAt: AT,
};

const VERSION = {
  id: "v1",
  template: "t1",
  version: 1,
  hash: "abc",
  publishedAt: AT,
  createdBy: "u1",
  createdAt: AT,
  body: {},
};

const applies: { values: unknown; key: string | undefined }[] = [];

const invoice = defineTemplateType({
  settings: v.object({}),
  body: v.object({}),
  apply: (call) => {
    applies.push({ values: call.values, key: call.key });

    return { subject: { type: "invoice", id: "i1" } };
  },
});

function jobs(duplicateKeys: readonly string[] = []) {
  const enqueued: { payload: unknown; options: unknown }[] = [];

  const queue: TemplateJobs = {
    enqueueOnce: (_queue, payload, options) => {
      enqueued.push({ payload, options });

      return AsyncResult.ok({
        id: 1,
        duplicate: duplicateKeys.includes(options.dedupeKey),
      });
    },
  };

  return { queue, enqueued };
}

describe("recurring templates", () => {
  it("saves, lists and removes schedules", async () => {
    const fake = transport({
      save_template_schedule: () => SCHEDULE,
      template_schedules_list: () => [SCHEDULE, { ...SCHEDULE, tzid: null }],
      remove_template_schedule: () => true,
    });

    const { recurring } = createTemplates({ transport: fake });

    const saved = await recurring
      .upsert({
        template: "t1",
        organizationId: "o",
        dtstart: Temporal.Instant.from("2026-10-01T09:00:00Z"),
        rrule: "FREQ=DAILY",
      })
      .orThrow();

    expect(saved).toMatchObject({
      id: "s1",
      organizationId: "o",
      input: { owner: "u1" },
      enabled: true,
    });
    expect(fake.calls[0]).toEqual([
      "save_template_schedule",
      {
        schedule_id: null,
        template_id: "t1",
        tenant: "o",
        dtstart: "2026-10-01T09:00:00Z",
        tzid: "UTC",
        rrule: "FREQ=DAILY",
        input: {},
        enabled: true,
      },
    ]);

    await recurring
      .upsert({
        id: "s1",
        template: "t1",
        organizationId: "o",
        dtstart: Temporal.Instant.from("2026-10-01T09:00:00Z"),
        tzid: "Europe/Amsterdam",
        rrule: "FREQ=WEEKLY",
        input: { owner: "u2" },
        enabled: false,
      })
      .orThrow();

    expect(fake.calls[1]?.[1]).toMatchObject({
      schedule_id: "s1",
      tzid: "Europe/Amsterdam",
      enabled: false,
    });

    const listed = await recurring.list({ organizationId: "o" }).orThrow();
    expect(listed.map((row) => row.tzid)).toEqual(["UTC", "UTC"]);
    expect(fake.calls[2]).toEqual([
      "template_schedules_list",
      { tenant: "o", template_id: null },
    ]);

    await recurring.list({ organizationId: "o", template: "t1" }).orThrow();
    expect(fake.calls[3]?.[1]).toEqual({ tenant: "o", template_id: "t1" });

    expect(await recurring.remove("s1").orThrow()).toBe(true);
  });

  it("enqueues each occurrence in the window once", async () => {
    const fake = transport({
      list_template_schedule: () => [
        SCHEDULE,
        { ...SCHEDULE, id: "bad", rrule: "FREQ=NEVER" },
      ],
    });

    const { queue, enqueued } = jobs(["s1:2026-10-06T09:00:00Z"]);
    const { recurring } = createTemplates({ transport: fake, jobs: queue });

    const result = await recurring
      .schedule({
        now: Temporal.Instant.from("2026-10-06T09:05:00Z"),
        horizonMinutes: 24 * 60,
      })
      .orThrow();

    expect(result).toEqual({
      planned: 2,
      enqueued: 1,
      duplicates: 1,
      skipped: 1,
    });
    expect(enqueued[0]).toEqual({
      payload: {
        schedule: "s1",
        occurrenceAt: "2026-10-06T09:00:00Z",
        organizationId: "o",
      },
      options: {
        dedupeKey: "s1:2026-10-06T09:00:00Z",
        runAt: Temporal.Instant.from("2026-10-06T09:05:00Z"),
        context: { tenant: "o" },
      },
    });
    expect(enqueued[1]?.options).toMatchObject({
      runAt: Temporal.Instant.from("2026-10-07T09:00:00Z"),
    });
  });

  it("uses the default window and fails without a jobs queue", async () => {
    const fake = transport({ list_template_schedule: () => [] });

    const missing = await createTemplates({
      transport: fake,
    }).recurring.schedule();

    expect(missing.ok ? undefined : missing.error.hint).toBe(
      "TEMPLATE_JOBS_MISSING",
    );

    const { queue } = jobs();

    const empty = await createTemplates({ transport: fake, jobs: queue })
      .recurring.schedule()
      .orThrow();

    expect(empty).toEqual({
      planned: 0,
      enqueued: 0,
      duplicates: 0,
      skipped: 0,
    });
  });

  it("passes on a failed list or enqueue", async () => {
    const failing = transport({
      list_template_schedule: () => Promise.reject(new Error("down")),
    });

    const { queue } = jobs();

    const listed = await createTemplates({
      transport: failing,
      jobs: queue,
    }).recurring.schedule();

    expect(listed.ok).toBe(false);

    const refusing: TemplateJobs = {
      enqueueOnce: () => AsyncResult.err(dbError("unexpected", "queue down")),
    };

    const enqueued = await createTemplates({
      transport: transport({ list_template_schedule: () => [SCHEDULE] }),
      jobs: refusing,
    }).recurring.schedule({
      now: Temporal.Instant.from("2026-10-06T08:00:00Z"),
    });

    expect(enqueued.ok ? undefined : enqueued.error.message).toBe("queue down");
  });

  it("claims an occurrence, applies the template and records it", async () => {
    const fake = transport({
      claim_template_occurrence: () => SCHEDULE,
      template_apply_target: () => ({
        template: TEMPLATE,
        version: VERSION,
        workflows: [],
      }),
      record_template_application: () => ({
        id: "a1",
        template: "t1",
        version: "v1",
        tenant: "o",
        subjectType: "invoice",
        subjectId: "i1",
        appliedBy: null,
        appliedAt: AT,
      }),
      finish_template_occurrence: () => true,
    });

    const { recurring } = createTemplates({
      transport: fake,
      types: { invoice },
    });

    await recurring.job(
      {
        schedule: "s1",
        occurrenceAt: "2026-10-06T09:00:00Z",
        organizationId: "o",
      },
      undefined as never,
      signal,
    );

    expect(applies.at(-1)).toEqual({
      values: { owner: "u1" },
      key: "template-schedule:s1:2026-10-06T09:00:00Z",
    });
    expect(fake.calls.at(-1)).toEqual([
      "finish_template_occurrence",
      {
        schedule_id: "s1",
        occurrence_at: "2026-10-06T09:00:00Z",
        application_id: "a1",
      },
    ]);

    const direct = await recurring
      .run({
        schedule: "s1",
        occurrenceAt: Temporal.Instant.from("2026-10-06T09:00:00Z"),
      })
      .orThrow();

    expect(direct).toEqual({ status: "applied", application: "a1" });
  });

  it("skips an occurrence that was already claimed", async () => {
    const fake = transport({ claim_template_occurrence: () => null });
    const { recurring } = createTemplates({ transport: fake });

    const result = await recurring
      .run({
        schedule: "s1",
        occurrenceAt: Temporal.Instant.from("2026-10-06T09:00:00Z"),
      })
      .orThrow();

    expect(result).toEqual({ status: "skipped" });

    await recurring.job(
      {
        schedule: "s1",
        occurrenceAt: Temporal.Instant.from("2026-10-06T09:00:00Z"),
      },
      undefined as never,
      signal,
    );

    expect(fake.calls).toHaveLength(2);
    await expect(
      recurring.job("nope", undefined as never, signal),
    ).rejects.toThrow(TEMPLATE_RECUR_QUEUE);
  });

  it("plans occurrences in the schedule's time zone", () => {
    const { planned, skipped } = planOccurrences(
      [
        {
          id: "s1",
          template: "t1",
          organizationId: "o",
          input: {},
          enabled: true,
          dtstart: Temporal.Instant.from("2026-10-01T07:00:00Z"),
          tzid: "Europe/Amsterdam",
          rrule: "FREQ=DAILY",
          createdBy: undefined,
          createdAt: Temporal.Instant.from(AT),
          updatedAt: Temporal.Instant.from(AT),
        },
      ],
      {
        from: Temporal.Instant.from("2026-10-26T00:00:00Z"),
        until: Temporal.Instant.from("2026-10-27T00:00:00Z"),
      },
    );

    expect(skipped).toBe(0);
    expect(planned.map((row) => row.occurrenceAt.toString())).toEqual([
      "2026-10-26T08:00:00Z",
    ]);
  });

  it("declares the schedule in the manifest", () => {
    expect(templatesBlock.schedules).toEqual([
      expect.objectContaining({ runs: "recurring.schedule()" }),
    ]);
  });
});
