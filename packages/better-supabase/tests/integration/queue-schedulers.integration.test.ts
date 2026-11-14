import { Pool } from "pg";
import * as v from "valibot";
import { afterAll, describe, expect, it } from "vitest";

import {
  createQueue,
  sqlQueueProvider,
  sqlScheduler,
  vercelQueueProvider,
  vercelQueueRoute,
  vercelScheduleBridgeRoute,
  vercelScheduler,
} from "../../src/blocks/queue/index.ts";
import {
  testQueueProvider,
  testScheduleProvider,
} from "../../src/testing/index.ts";
import {
  fakeSchedules,
  fakeVercelQueues,
} from "../blocks/queue/vercel-fakes.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const queues = { it_sched: v.object({ n: v.number() }) };

const PROBES = `
  create or replace function public.bsb_it_work() returns boolean language sql as 'select true';
  create or replace function public.bsb_it_no_work() returns boolean language sql as 'select false';
`;

/** Installs the queue module, with pg_cron and pg_net, as the service role. */
async function session(
  pool: Pool,
  options: Readonly<Record<string, unknown>> = {},
): Promise<BlockSession> {
  const s = await BlockSession.open(pool);

  await s.client.query(
    "create extension if not exists pg_cron with schema pg_catalog",
  );
  await s.client.query("create extension if not exists pg_net");
  await s.client.query(PROBES);
  await s.install(["organizations", "outbox", "queue"], {
    modules: { queue: { options } },
  });
  await s.service();

  return s;
}

const waiting = (s: BlockSession, queue: string): Promise<number> =>
  s.value<number>(`(select count(*)::int from pgmq.q_${queue})`);

describe.skipIf(!live)("queues and schedulers", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("Supabase Queues with Supabase Cron: pg_cron enqueues, and a false probe enqueues nothing", async () => {
    const s = await session(pool);

    try {
      expect(
        (
          await testQueueProvider(sqlQueueProvider(s.sql), {
            queue: "it_pairs_cron",
          })
        ).checks.every((check) => check.ok),
      ).toBe(true);
      expect(
        (
          await testScheduleProvider(sqlScheduler(s.sql), {
            prefix: "it:cron:",
            queue: "it_sched",
            probe: "public.bsb_it_work",
          })
        ).checks.every((check) => check.ok),
      ).toBe(true);

      const jobs = createQueue({ sql: s.sql, queues });

      for (const [name, probe] of [
        ["it:none", "public.bsb_it_no_work"],
        ["it:some", "public.bsb_it_work"],
      ] as const) {
        await jobs
          .schedule({
            name,
            cron: "0 3 * * *",
            queue: "it_sched",
            payload: { n: 1 },
            probe,
          })
          .orThrow();
      }

      const [none] = await s.rows<{ command: string }>(
        "select command from cron.job where jobname = 'it:none'",
      );

      await s.rows(none!.command);
      expect(await waiting(s, "it_sched")).toBe(0);

      const [some] = await s.rows<{ command: string }>(
        "select command from cron.job where jobname = 'it:some'",
      );

      await s.rows(some!.command);
      expect(await waiting(s, "it_sched")).toBe(1);
    } finally {
      await s.close();
    }
  });

  it("Supabase Queues with Vercel Schedules: the bridge checks the probe and enqueues each run once", async () => {
    const s = await session(pool);

    try {
      const schedules = fakeSchedules();
      const vq = fakeVercelQueues();

      const jobs = createQueue({
        sql: s.sql,
        scheduler: vercelScheduler(schedules.client, {
          bridge: "bsb_schedules",
        }),
        queues,
      });

      vercelScheduleBridgeRoute(jobs, { client: vq.client });

      await jobs
        .schedule({
          name: "it:daily",
          cron: "0 9 * * *",
          queue: "it_sched",
          payload: { n: 2 },
        })
        .orThrow();
      await jobs
        .schedule({
          name: "it:idle",
          cron: "0 9 * * *",
          queue: "it_sched",
          payload: { n: 3 },
          probe: "public.bsb_it_no_work",
        })
        .orThrow();

      const daily = schedules.fire("it_3adaily", "better-supabase");

      vq.publish(daily.topic, daily.message);
      vq.publish(daily.topic, daily.message);

      const idle = schedules.fire("it_3aidle", "better-supabase");

      vq.publish(idle.topic, idle.message);

      expect(await vq.deliver("bsb_schedules")).toEqual([]);
      expect(await waiting(s, "it_sched")).toBe(1);

      const [job] = await jobs.claim({ queue: "it_sched" }).orThrow();

      expect(job?.payload).toEqual({ n: 2 });
    } finally {
      await s.close();
    }
  });

  it("Vercel Queues with Supabase Cron: the drain scheduler sends due runs to the topic", async () => {
    const s = await session(pool, { scheduler: "drain" });

    try {
      expect(
        (
          await testScheduleProvider(sqlScheduler(s.sql, { mode: "drain" }), {
            prefix: "it:drain:",
            queue: "it_sched",
            tenant: "it-tenant",
            probe: "public.bsb_it_work",
          })
        ).checks.every((check) => check.ok),
      ).toBe(true);

      const vq = fakeVercelQueues();

      const jobs = createQueue({
        backend: vercelQueueProvider(vq.client),
        scheduler: sqlScheduler(s.sql, { mode: "drain" }),
        queues,
      });

      await jobs
        .schedule({
          name: "it:due",
          cron: "* * * * *",
          queue: "it_sched",
          payload: { n: 4 },
        })
        .orThrow();
      await jobs
        .schedule({
          name: "it:idle",
          cron: "* * * * *",
          queue: "it_sched",
          payload: { n: 5 },
          probe: "public.bsb_it_no_work",
        })
        .orThrow();
      await s.rows(
        "update better_supabase.job_schedules set next_run = clock_timestamp() - interval '1 minute' where job_name like 'it:%'",
      );

      const route = jobs.schedulesRoute({ secret: "s3cret" });

      const response = await route(
        new Request("https://app.test/api/jobs/schedules", {
          method: "POST",
          headers: { authorization: "Bearer s3cret" },
        }),
      );

      expect(await response.json()).toEqual({ schedules: 1, errors: 0 });
      expect(vq.open("it_sched")).toEqual([
        { payload: { n: 4 }, max_attempts: 5 },
      ]);

      const [idle] = await s.rows<{ due: boolean }>(
        "select next_run <= clock_timestamp() as due from better_supabase.job_schedules where job_name = 'it:idle'",
      );

      expect(idle?.due).toBe(true);

      const seen: unknown[] = [];

      vercelQueueRoute(jobs, {
        client: vq.client,
        handlers: { it_sched: (payload) => void seen.push(payload) },
      });

      expect(await vq.deliver("it_sched")).toEqual([]);
      expect(seen).toEqual([{ n: 4 }]);
    } finally {
      await s.close();
    }
  });

  it("Vercel Queues with Vercel Schedules: runs publish to the job's topic", async () => {
    const schedules = fakeSchedules();
    const vq = fakeVercelQueues();
    const seen: unknown[] = [];

    const jobs = createQueue({
      backend: vercelQueueProvider(vq.client),
      scheduler: vercelScheduler(schedules.client),
      queues,
    });

    vercelQueueRoute(jobs, {
      client: vq.client,
      handlers: { it_sched: (payload) => void seen.push(payload) },
    });

    await jobs
      .schedule({
        name: "it:direct",
        cron: "0 9 * * *",
        queue: "it_sched",
        payload: { n: 6 },
      })
      .orThrow();

    const run = schedules.fire("it_3adirect", "better-supabase");

    vq.publish(run.topic, run.message);
    expect(await vq.deliver("it_sched")).toEqual([]);
    expect(seen).toEqual([{ n: 6 }]);
  });

  it("http_tick posts with the Vault secrets, and httpTick registers it with pg_cron", async () => {
    const s = await session(pool, { httpTick: true });

    try {
      const [job] = await s.rows<{ schedule: string; command: string }>(
        "select schedule, command from cron.job where jobname = 'bsb_jobs_tick'",
      );

      expect(job).toEqual({
        schedule: "* * * * *",
        command: "select better_supabase.http_tick()",
      });
      expect(await s.value("better_supabase.http_tick()")).toBeNull();

      await s.rows(
        "select vault.create_secret('http://127.0.0.1:9/api/jobs/drain', 'jobs_tick_url'), vault.create_secret('tick-token', 'jobs_tick_token')",
      );

      const id = await s.value<string>("better_supabase.http_tick()");

      expect(Number(id)).toBeGreaterThan(0);

      const [sent] = await s.rows<{ url: string; auth: string }>(
        "select url, headers ->> 'authorization' as auth from net.http_request_queue where id = $1",
        [id],
      );

      expect(sent).toEqual({
        url: "http://127.0.0.1:9/api/jobs/drain",
        auth: "Bearer tick-token",
      });
    } finally {
      await s.close();
    }
  });
});
