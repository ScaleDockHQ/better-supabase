import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { startFor, WORKFLOW_ATTRIBUTES } from "../../src/workflow-sdk/index.ts";
import {
  createSupabaseWorld,
  type SupabaseWorld,
} from "../../src/workflow-sdk/world/index.ts";
import { dbUrl, reachable } from "./block-session.ts";
import { installWorld } from "./workflow-world.ts";

const live = await reachable();

const ACME = "00000000-0000-4000-8000-000000000001";
const ADMIN = "00000000-0000-4000-8000-0000000000a1";
const FOREIGN_TENANT = "00000000-0000-4000-8000-0000000000f9";
const KEY = `test:${crypto.randomUUID()}`;
const SUFFIX = crypto.randomUUID().slice(0, 8);
const STEP = `step_${SUFFIX}`;
const HOOK = `hook_${SUFFIX}`;
const WAIT = `wait_${SUFFIX}`;

const pool = new Pool({ connectionString: dbUrl });
let world: SupabaseWorld;
const created: string[] = [];

async function createRun(
  workflowName: string,
  attributes: Record<string, string>,
): Promise<string> {
  const result = await world.events.create(null, {
    eventType: "run_created",
    eventData: {
      deploymentId: "test",
      workflowName,
      input: [],
      attributes,
    },
  });
  const runId = result.run.runId;
  created.push(runId);
  return runId;
}

beforeAll(async () => {
  if (!live) return;
  await installWorld(pool);
  world = createSupabaseWorld({ pool });
});

afterAll(async () => {
  if (live) {
    await pool.query(
      "delete from better_supabase.workflow_runs where external_id = any($1)",
      [created],
    );
    for (const table of ["events", "steps", "hooks", "waits", "runs"])
      await pool.query(
        `delete from workflow.workflow_${table} where ${table === "runs" ? "id" : "run_id"} = any($1)`,
        [created],
      );
    await world.close();
  }
  await pool.end();
});

describe.skipIf(!live)("Supabase World", () => {
  const mirrored = async (runId: string) =>
    (
      await pool.query<{
        engine: string;
        status: string;
        tenant: string | null;
        actor: string | null;
        attributes: Record<string, string>;
      }>(
        `select engine, status, tenant_id::text as tenant, actor_id::text as actor, attributes
           from better_supabase.workflow_runs where external_id = $1`,
        [runId],
      )
    ).rows[0];

  it("copies a server-started run into workflow_runs with its tenant", async () => {
    const runId = await createRun("workflow//./approve//approve", {
      [WORKFLOW_ATTRIBUTES.tenant]: ACME,
      customer: "c_1",
    });
    expect(await mirrored(runId)).toMatchObject({
      engine: "workflow-sdk",
      status: "queued",
      tenant: ACME,
      actor: null,
      attributes: { customer: "c_1" },
    });
  });

  it("drops the tenant of a run whose actor can't run workflows there", async () => {
    const runId = await createRun("workflow//./approve//approve", {
      [WORKFLOW_ATTRIBUTES.tenant]: FOREIGN_TENANT,
      [WORKFLOW_ATTRIBUTES.actor]: ADMIN,
    });
    expect(await mirrored(runId)).toMatchObject({ tenant: null, actor: ADMIN });
  });

  it("lists runs, attributes and events through analytics", async () => {
    const runId = await createRun("workflow//./keyed//keyed", {
      [WORKFLOW_ATTRIBUTES.key]: KEY,
    });
    const analytics = world.analytics;
    if (analytics === undefined) throw new Error("no analytics");

    const runs = await analytics.runs.list({
      attributes: { [WORKFLOW_ATTRIBUTES.key]: KEY },
    });
    expect(runs.data.map((run) => run.runId)).toEqual([runId]);
    expect(runs.hasMore).toBe(false);

    const byName = await analytics.runs.list({
      workflowName: "workflow//./keyed//keyed",
      pagination: { limit: 1 },
    });
    expect(byName.data).toHaveLength(1);

    const keys = await analytics.attributes.list({});
    expect(keys.data.map((entry) => entry.key)).toContain(
      WORKFLOW_ATTRIBUTES.key,
    );

    const events = await analytics.events.list({ runId });
    expect(events.data.map((event) => event.eventType)).toContain(
      "run_created",
    );

    await expect(
      analytics.runs.list({ pagination: { limit: 101 } }),
    ).rejects.toThrow(RangeError);
  });

  it("reads steps, hooks, waits and events of a run", async () => {
    const runId = await createRun("workflow//./parts//parts", {});
    await world.events.create(runId, { eventType: "run_started" });
    await world.events.create(runId, {
      eventType: "step_created",
      correlationId: STEP,
      eventData: { stepName: "send", input: [] },
    });
    await world.events.create(runId, {
      eventType: "hook_created",
      correlationId: HOOK,
      eventData: { token: `token-${crypto.randomUUID()}` },
    });
    await world.events.create(runId, {
      eventType: "wait_created",
      correlationId: WAIT,
      eventData: { resumeAt: new Date(Date.now() + 60_000) },
    });
    const analytics = world.analytics!;

    expect((await analytics.runs.get(runId)).status).toBe("running");
    expect(await analytics.steps.get(runId, STEP)).toMatchObject({
      stepName: "send",
      status: "pending",
    });
    expect((await analytics.steps.list({ runId })).data).toHaveLength(1);
    expect(await analytics.hooks.get(HOOK, { runId })).toMatchObject({
      status: "created",
      runId,
    });
    expect((await analytics.hooks.list({ runId })).data).toHaveLength(1);
    expect(await analytics.waits.get(runId, WAIT)).toMatchObject({
      waitId: WAIT,
      status: "waiting",
    });
    expect(
      (await analytics.waits.list({ runId, status: "waiting" })).data,
    ).toHaveLength(1);

    const page = await analytics.events.list({
      runId,
      pagination: { limit: 2, sortOrder: "asc" },
    });
    expect(page.data.map((event) => event.eventType)).toEqual([
      "run_created",
      "run_started",
    ]);
    expect(page.hasMore).toBe(true);
    const next = await analytics.events.list({
      runId,
      pagination: { limit: 2, sortOrder: "asc", cursor: page.cursor! },
    });
    expect(next.data[0]?.eventType).toBe("step_created");
    expect(next.data[0]?.stepName).toBe("send");
    const step = await analytics.events.list({
      runId,
      correlationId: STEP,
    });
    expect(step.data).toHaveLength(1);
    const event = await analytics.events.get(runId, step.data[0]!.eventId);
    expect(event.correlationId).toBe(STEP);
    expect(
      await analytics.events.getMany(runId, [event.eventId, event.eventId]),
    ).toHaveLength(1);
    await expect(analytics.steps.get(runId, "nope")).rejects.toThrow(
      'workflow step "nope" not found',
    );
    const now = new Date();
    const windowed = await analytics.runs.list({
      workflowName: "workflow//./parts//parts",
      startTime: new Date(now.getTime() - 60_000).toISOString(),
      endTime: new Date(now.getTime() + 60_000).toISOString(),
    });
    expect(windowed.data.map((run) => run.runId)).toContain(runId);
  });

  it("returns the existing run for an idempotency key", async () => {
    const runId = await createRun("workflow//./once//once", {
      [WORKFLOW_ATTRIBUTES.key]: `${KEY}:once`,
    });
    const run = await startFor(
      { tenant: ACME },
      async () => {
        throw new Error("must not start");
      },
      [],
      { idempotencyKey: `${KEY}:once`, world },
    );
    expect(run.runId).toBe(runId);
  });
});
