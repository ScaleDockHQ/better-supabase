import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import {
  createWorkflows,
  sqlTransport,
  type WorkflowStartCall,
} from "../../src/blocks/workflows/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

describe.skipIf(!live)("workflows module", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("records runs that their actor and the tenant read, and cancels them", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "outbox", "workflows"]);
      const owner = await s.user("owner");
      const member = await s.user("member");
      const outsider = await s.user("outsider");
      const tenant = await s.organization(owner, { member });
      await s.service();
      const service = createWorkflows({ transport: sqlTransport(s.sql) });
      const id = await service.runs
        .record({
          engine: "workflow-sdk",
          externalId: "wrun_1",
          definition: "onboard",
          status: "running",
          tenant,
          actor: member.id,
          attributes: { plan: "pro" },
        })
        .orThrow();
      await service.runs
        .record({
          engine: "workflow-sdk",
          externalId: "wrun_2",
          definition: "report",
          status: "queued",
          tenant,
        })
        .orThrow();

      await s.asRole(member);
      const workflows = createWorkflows({ transport: sqlTransport(s.sql) });
      const mine = await workflows.runs.list({ tenant }).orThrow();
      expect(mine.map((run) => run.externalId)).toEqual(["wrun_1"]);
      expect(mine[0]).toMatchObject({
        id,
        status: "running",
        attributes: { plan: "pro" },
      });
      expect((await workflows.runs.get("wrun_1").orThrow())?.id).toBe(id);

      await s.asRole(owner);
      expect(
        (await workflows.runs.list({ tenant }).orThrow())
          .map((run) => run.externalId)
          .toSorted(),
      ).toEqual(["wrun_1", "wrun_2"]);

      await s.asRole(outsider);
      expect(await workflows.runs.list({ tenant }).orThrow()).toEqual([]);
      expect(await workflows.runs.get(id).orThrow()).toBeUndefined();
      await s.as(outsider);
      expect(
        await s.hint("better_supabase.request_workflow_cancel($1)", [id]),
      ).toBe("WORKFLOW_FORBIDDEN");

      await s.as(member);
      const cancelled = await workflows.runs.requestCancel(id).orThrow();
      expect(cancelled?.cancelRequestedAt).toBeDefined();

      await s.service();
      await service.runs
        .record({
          engine: "workflow-sdk",
          externalId: "wrun_1",
          definition: "onboard",
          status: "cancelled",
          completedAt: Temporal.Now.instant(),
        })
        .orThrow();
      const events = await s.rows<{ type: string; organization_id: string }>(
        "select type, organization_id from better_supabase.outbox_events where type like 'workflow.run.%' and payload ->> 'runId' = $1",
        [id],
      );
      expect(events).toEqual([
        { type: "workflow.run.cancelled", organization_id: tenant },
      ]);
      const kept = await service.runs.get(id).orThrow();
      expect(kept).toMatchObject({ tenant, actor: member.id });
    } finally {
      await s.close();
    }
  });

  it("fires due schedules once with a stable idempotency key", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "workflows"]);
      const owner = await s.user("owner");
      const member = await s.user("member");
      const tenant = await s.organization(owner, { member });

      await s.as(member);
      const asMember = createWorkflows({ transport: sqlTransport(s.sql) });
      expect(
        await asMember.schedules
          .create({ name: "daily", workflow: "report", cron: "@daily", tenant })
          .then((result) => !result.ok && result.error.hint),
      ).toBe("WORKFLOW_FORBIDDEN");

      await s.as(owner);
      const workflows = createWorkflows({ transport: sqlTransport(s.sql) });
      const schedule = await workflows.schedules
        .create({
          name: "daily",
          workflow: "report",
          cron: "0 9 * * *",
          timezone: "Europe/Amsterdam",
          input: [{ kind: "daily" }],
          tenant,
        })
        .orThrow();
      expect(() =>
        workflows.schedules.create({
          name: "bad",
          workflow: "x",
          cron: "not cron",
        }),
      ).toThrow('Invalid cron "not cron"');

      await s.service();
      const service = createWorkflows({ transport: sqlTransport(s.sql) });
      const starts: WorkflowStartCall[] = [];
      const start = async (call: WorkflowStartCall): Promise<string> => {
        starts.push(call);
        return `wrun_${String(starts.length)}`;
      };
      expect(await service.schedules.tick({ start }).orThrow()).toEqual({
        started: 0,
        failed: [],
      });

      await s.client.query(
        "update better_supabase.workflow_schedules set next_run_at = now() - interval '1 minute' where id = $1",
        [schedule.id],
      );
      const fired = await s.value<string>(
        "(select next_run_at::text from better_supabase.workflow_schedules where id = $1)",
        [schedule.id],
      );
      expect(await service.schedules.tick({ start }).orThrow()).toMatchObject({
        started: 1,
      });
      expect(starts[0]).toMatchObject({
        workflow: "report",
        input: [{ kind: "daily" }],
        tenant,
        actor: owner.id,
      });
      expect(starts[0]?.idempotencyKey).toMatch(
        new RegExp(`^schedule:${schedule.id}:`),
      );
      const [after] = await service.schedules.list(tenant).orThrow();
      expect(after?.lastRunAt?.toString()).toBe(
        Temporal.Instant.from(fired.replace(" ", "T")).toString(),
      );
      expect(
        Temporal.Instant.compare(after!.nextRunAt, Temporal.Now.instant()),
      ).toBe(1);
      expect(await service.schedules.tick({ start }).orThrow()).toMatchObject({
        started: 0,
      });

      expect(await workflows.schedules.pause(schedule.id).orThrow()).toBe(true);
      expect(await workflows.schedules.remove(schedule.id).orThrow()).toBe(
        true,
      );
    } finally {
      await s.close();
    }
  });

  it("counts semaphore holders and admits starts by concurrency, debounce and singleton", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "workflows"]);
      await s.service();
      const workflows = createWorkflows({ transport: sqlTransport(s.sql) });

      expect(
        await workflows.semaphores.acquire("api", "a", { max: 1 }).orThrow(),
      ).toBe(true);
      expect(
        await workflows.semaphores.acquire("api", "a", { max: 1 }).orThrow(),
      ).toBe(true);
      expect(
        await workflows.semaphores.acquire("api", "b", { max: 1 }).orThrow(),
      ).toBe(false);
      expect(await workflows.semaphores.release("api", "a").orThrow()).toBe(
        true,
      );
      expect(
        await workflows.semaphores.acquire("api", "b", { max: 1 }).orThrow(),
      ).toBe(true);

      const started: string[] = [];
      const start = async (call: WorkflowStartCall): Promise<string> => {
        started.push(call.idempotencyKey);
        return `wrun_${String(started.length)}`;
      };

      for (let index = 0; index < 3; index += 1) {
        await workflows.admission
          .request({ key: "sync", workflow: "sync", concurrency: 2 })
          .orThrow();
      }
      expect(await workflows.admission.tick({ start }).orThrow()).toMatchObject(
        { started: 2 },
      );
      expect(await workflows.admission.tick({ start }).orThrow()).toMatchObject(
        { started: 0 },
      );
      await workflows.runs
        .record({
          engine: "workflow-sdk",
          externalId: "wrun_1",
          definition: "sync",
          status: "completed",
        })
        .orThrow();
      expect(await workflows.admission.tick({ start }).orThrow()).toMatchObject(
        { started: 1 },
      );

      const first = await workflows.admission
        .request({ key: "one", workflow: "export", singleton: true })
        .orThrow();
      expect(first.status).toBe("pending");
      expect(
        await workflows.admission
          .request({ key: "one", workflow: "export", singleton: true })
          .orThrow(),
      ).toEqual({ id: undefined, status: "dropped" });

      await workflows.admission
        .request({ key: "typing", workflow: "index", debounce: 60 })
        .orThrow();
      await workflows.admission
        .request({ key: "typing", workflow: "index", debounce: 60 })
        .orThrow();
      const statuses = await s.rows<{ status: string }>(
        "select status from better_supabase.workflow_start_requests where key = 'typing' order by created_at, status",
      );
      expect(statuses.map((row) => row.status).toSorted()).toEqual([
        "pending",
        "superseded",
      ]);
      const before = started.length;
      await workflows.admission.tick({ start }).orThrow();
      expect(started.length - before).toBe(1);
    } finally {
      await s.close();
    }
  });
});
