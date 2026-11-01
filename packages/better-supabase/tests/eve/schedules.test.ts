import { describe, expect, it, vi } from "vitest";

import type {
  EveAgentJob,
  EveQueueJob,
  EveScheduleArgs,
  EveSessionAuth,
  EveTargetHandle,
} from "../../src/eve/index.ts";

import { AsyncResult } from "../../src/core/result.ts";
import {
  eveAgentJob,
  jobAuth,
  queueSchedules,
  scheduleAgent,
} from "../../src/eve/index.ts";

const USER = "11111111-1111-4111-8111-111111111111";
const ORG = "22222222-2222-4222-8222-222222222222";

const appAuth: EveSessionAuth = {
  authenticator: "app",
  principalType: "runtime",
  principalId: "eve:app",
  attributes: {},
};

const slack = { name: "slack" };

function scheduleArgs() {
  const sent: {
    channel: unknown;
    target: unknown;
    message: string;
    auth: EveSessionAuth | null;
  }[] = [];

  const tasks: Promise<unknown>[] = [];

  const to = (channel: unknown, target: unknown): EveTargetHandle => ({
    send: (message, { auth }) => {
      sent.push({ channel, target, message, auth });

      return Promise.resolve({ id: "sess" });
    },
  });

  const args: EveScheduleArgs = {
    to,
    appAuth,
    waitUntil: (task) => {
      tasks.push(task);
    },
  };

  return { args, sent, tasks };
}

/** A queue that hands `jobs` to the handler once, as `drain` does. */
function fakeQueue(jobs: readonly (readonly [EveAgentJob, EveQueueJob])[]) {
  return {
    runSchedules: vi.fn(() => AsyncResult.ok(0)),
    drain: vi.fn(
      async ({
        handler,
      }: {
        queue: string;
        handler: (payload: EveAgentJob, job: EveQueueJob) => unknown;
        budgetMs?: number | undefined;
      }) => {
        let failed = 0;

        for (const [payload, job] of jobs) {
          try {
            await handler(payload, job);
          } catch {
            failed += 1;
          }
        }

        return { succeeded: jobs.length - failed, failed };
      },
    ),
  };
}

describe("queueSchedules", () => {
  it("drains the eve queue and sends each job as its user", async () => {
    const queue = fakeQueue([
      [
        {
          prompt: "Send the digest",
          channel: "slack",
          target: { channelId: "C1" },
        },
        { context: { actor: { id: USER, kind: "user" }, tenant: ORG } },
      ],
      [
        { prompt: "Check the status page", channel: "slack", target: null },
        { context: {} },
      ],
    ]);

    const { args, sent, tasks } = scheduleArgs();

    queueSchedules({ queue, channels: { slack } })(args);

    expect(tasks).toHaveLength(1);
    await expect(tasks[0]).resolves.toEqual({ succeeded: 2, failed: 0 });
    expect(queue.runSchedules).toHaveBeenCalledOnce();
    expect(queue.drain).toHaveBeenCalledWith({
      queue: "eve",
      handler: expect.any(Function),
      budgetMs: 50_000,
    });
    expect(sent).toEqual([
      {
        channel: slack,
        target: { channelId: "C1" },
        message: "Send the digest",
        auth: {
          authenticator: "supabase",
          principalType: "user",
          principalId: USER,
          subject: USER,
          attributes: { tenantId: ORG },
        },
      },
      {
        channel: slack,
        target: null,
        message: "Check the status page",
        auth: appAuth,
      },
    ]);
  });

  it("fails a job whose channel is not configured", async () => {
    const queue = fakeQueue([
      [{ prompt: "Hi", channel: "teams", target: null }, { context: {} }],
    ]);

    const { args, sent, tasks } = scheduleArgs();

    queueSchedules({ queue, channels: { slack }, queueName: "agents" })(args);

    await expect(tasks[0]).resolves.toEqual({ succeeded: 0, failed: 1 });
    expect(queue.drain).toHaveBeenCalledWith({
      queue: "agents",
      handler: expect.any(Function),
      budgetMs: expect.anything(),
    });
    expect(sent).toEqual([]);
  });
});

describe("jobAuth", () => {
  it("uses the app principal for a service job", () => {
    expect(jobAuth({ actor: { id: "svc", kind: "service" } }, appAuth)).toBe(
      appAuth,
    );
  });
});

describe("scheduleAgent", () => {
  it("writes a queue block schedule on the eve queue", async () => {
    const schedule = vi.fn(() => AsyncResult.ok(undefined));
    const job = { prompt: "Weekly report", channel: "slack", target: null };

    await scheduleAgent({ schedule }, "report:org", "0 9 * * 1", job, {
      timeZone: "Europe/Amsterdam",
      context: { actor: { id: USER, kind: "user" }, tenant: ORG },
    }).orThrow();

    expect(schedule).toHaveBeenCalledWith({
      name: "report:org",
      cron: "0 9 * * 1",
      queue: "eve",
      payload: job,
      timeZone: "Europe/Amsterdam",
      context: { actor: { id: USER, kind: "user" }, tenant: ORG },
    });
  });
});

describe("eveAgentJob", () => {
  it("accepts a job and refuses one without a prompt or channel", async () => {
    const validate = eveAgentJob["~standard"].validate;

    expect(
      await validate({ prompt: "Hi", channel: "slack", target: { id: 1 } }),
    ).toEqual({ value: { prompt: "Hi", channel: "slack", target: { id: 1 } } });
    expect(await validate({ prompt: "Hi", channel: "slack" })).toEqual({
      value: { prompt: "Hi", channel: "slack", target: null },
    });
    expect(await validate({ prompt: "", channel: "slack" })).toHaveProperty(
      "issues",
    );
    expect(await validate("Hi")).toHaveProperty("issues");
  });
});
