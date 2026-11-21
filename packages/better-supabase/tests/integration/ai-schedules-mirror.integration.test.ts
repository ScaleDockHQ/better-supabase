import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import {
  createAiSchedules,
  sqlTransport,
} from "../../src/blocks/ai-schedules/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

describe.skipIf(!live)("ai-schedules mirrored tasks", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("stores another scheduler's task, records its runs and never executes it", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["organizations", "ai-schedules"]);
      const owner = await s.user("owner");
      const tenant = await s.organization(owner);
      const ran: string[] = [];

      const schedules = createAiSchedules({
        transport: sqlTransport(s.sql),
        run: async (task) => {
          ran.push(task.id);
        },
      });

      await s.service();

      const input = {
        organizationId: tenant,
        source: "eve",
        externalId: "eve:requests:ns:digest",
      };

      const mirrored = await schedules
        .mirror({
          ...input,
          userId: owner.id,
          task: {
            title: "Digest",
            prompt: "Send the digest",
            cron: "* * * * *",
          },
          nextRunAt: Temporal.Instant.from("2020-01-01T08:00:00Z"),
        })
        .orThrow();

      expect(mirrored).toMatchObject({ source: "eve", enabled: true });

      // The task is due, and ai-schedules leaves it alone.
      expect(await schedules.tick().orThrow()).toEqual([]);
      expect(await schedules.drain().orThrow()).toBe(0);
      expect(ran).toEqual([]);

      const at = Temporal.Instant.from("2020-01-01T08:00:00Z");

      const running = await schedules
        .recordRun({ ...input, scheduledFor: at, status: "running" })
        .orThrow();

      expect(running.status).toBe("running");

      const failed = await schedules
        .recordRun({
          ...input,
          scheduledFor: at,
          status: "failed",
          error: "the creator lost access",
        })
        .orThrow();

      expect(failed).toMatchObject({
        id: running.id,
        status: "failed",
        error: "the creator lost access",
      });
      expect(failed.finishedAt).toBeDefined();

      const unknown = await schedules.recordRun({
        ...input,
        externalId: "missing",
        scheduledFor: at,
        status: "completed",
      });

      expect(unknown.ok ? undefined : unknown.error.kind).toBe("not_found");

      expect(await schedules.unmirror(input).orThrow()).toBe(true);
      expect(await schedules.unmirror(input).orThrow()).toBe(false);
    } finally {
      await s.close();
    }
  });

  it("keeps running the tasks it owns next to a mirror", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["organizations", "ai-schedules"]);
      const owner = await s.user("owner");
      const tenant = await s.organization(owner);
      const ran: string[] = [];

      const schedules = createAiSchedules({
        transport: sqlTransport(s.sql),
        run: async (task) => {
          ran.push(task.title);
        },
      });

      await s.service();
      await s.client.query(
        `insert into better_supabase.ai_scheduled_tasks (tenant_id, user_id, title, prompt, cron, next_run_at)
         values ($1, $2, 'Native', 'Run', '* * * * *', now() - interval '1 minute')`,
        [tenant, owner.id],
      );
      await schedules
        .mirror({
          organizationId: tenant,
          userId: owner.id,
          source: "eve",
          externalId: "eve:a",
          task: { title: "Mirror", prompt: "Run", cron: "* * * * *" },
          nextRunAt: Temporal.Instant.from("2020-01-01T08:00:00Z"),
        })
        .orThrow();

      expect(await schedules.drain().orThrow()).toBe(1);
      expect(ran).toEqual(["Native"]);
    } finally {
      await s.close();
    }
  });
});
