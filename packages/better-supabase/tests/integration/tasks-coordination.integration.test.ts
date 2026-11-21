import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";
import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { createPipelines } from "../../src/blocks/pipelines/index.ts";
import { createTasks } from "../../src/blocks/tasks/index.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = [
  "organizations",
  "outbox",
  "notifications",
  "subjects",
  "rank",
  "relations",
  "pipelines",
  "messaging",
  "tasks",
];

const layout = (): BlockSqlLayout => ({
  subjects: withBlockSubjects({}, ["tasks"], {}),
  modules: {
    tasks: {
      tables: { projects: "work_projects" },
      options: {
        needs: { kind: "blocks" },
        claims: { lease: 60, maxLease: 600 },
      },
    },
  },
});

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

describe.skipIf(!live)("task coordination", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  /** An organization with an owner, two members and a team pipeline. */
  const setup = async () => {
    const s = await BlockSession.open(pool);
    const owner = await s.user("owner");
    const alice = await s.user("alice");
    const bob = await s.user("bob");
    await s.install(MODULES, layout());
    const org = await s.organization(owner, { member: alice, member2: bob });
    const transport = sqlTransport(s.sql);
    const tasks = createTasks({ transport });
    const pipelines = createPipelines({ transport });
    const team = crypto.randomUUID();

    return { s, owner, alice, bob, org, tasks, pipelines, team };
  };

  const stages = async (
    env: Awaited<ReturnType<typeof setup>>,
  ): Promise<(key: string) => string> => {
    await env.s.as(env.alice);
    await env.tasks
      .create({
        organizationId: env.org,
        input: { title: "seed", teamId: env.team },
      })
      .orThrow();

    const {
      items: [pipeline],
    } = await env.pipelines
      .page({ organizationId: env.org, filters: { subjectType: ["task"] } })
      .orThrow();

    return (key) => pipeline?.stages.find((item) => item.key === key)?.id ?? "";
  };

  it("keeps a task unready until its prerequisites are completed", async () => {
    const env = await setup();

    try {
      const { s, tasks, org, team } = env;
      const stage = await stages(env);
      await s.as(env.owner);

      const make = (title: string, needs?: string[]) =>
        tasks
          .create({
            organizationId: org,
            input: { title, teamId: team },
            ...(needs === undefined ? {} : { needs }),
          })
          .orThrow();

      const schema = await make("Design schema");
      const api = await make("Build API", [schema.id]);
      const ui = await make("Build UI", [api.id]);

      expect(schema.waitingOn).toBe(0);
      expect(api.waitingOn).toBe(1);
      expect(ui.waitingOn).toBe(1);

      const ready = async () =>
        (
          await tasks
            .page({
              organizationId: org,
              filters: { ready: ["true"] },
              limit: 50,
            })
            .orThrow()
        ).items
          .map((task) => task.title)
          .toSorted();

      expect(await ready()).toEqual(["Design schema", "seed"]);

      expect(hint(await tasks.claim({ taskId: api.id }))).toBe(
        "TASK_NOT_READY",
      );

      await tasks.complete({ taskId: schema.id }).orThrow();
      expect((await tasks.getTask(api.id).orThrow()).waitingOn).toBe(0);
      expect(await ready()).toEqual(["Build API", "seed"]);

      // A cancelled prerequisite keeps its dependents blocked.
      await tasks
        .cancel({ taskId: api.id, stageId: stage("canceled") })
        .orThrow();
      expect((await tasks.getTask(ui.id).orThrow()).waitingOn).toBe(1);

      expect(
        hint(await tasks.setNeeds({ taskId: schema.id, needs: [ui.id] })),
      ).toBe("RELATION_CYCLE");
    } finally {
      await env.s.close();
    }
  });

  it("refuses a prerequisite from another organization", async () => {
    const env = await setup();

    try {
      const { s, tasks, org, team, owner } = env;
      const stranger = await s.user("stranger");
      const other = await s.organization(stranger);
      await s.as(owner);

      const mine = await tasks
        .create({ organizationId: org, input: { title: "Mine", teamId: team } })
        .orThrow();

      await s.as(stranger);

      const theirs = await tasks
        .create({ organizationId: other, input: { title: "Theirs" } })
        .orThrow();

      await s.as(owner);

      const refused = await tasks.setNeeds({
        taskId: mine.id,
        needs: [theirs.id],
      });

      expect(refused.ok).toBe(false);
    } finally {
      await env.s.close();
    }
  });

  it("claims with a lease, tells claimers apart and loses an expired claim", async () => {
    const env = await setup();

    try {
      const { s, tasks, org, team, alice, bob } = env;
      await stages(env);
      await s.as(alice);

      const make = (title: string) =>
        tasks
          .create({ organizationId: org, input: { title, teamId: team } })
          .orThrow();

      const one = await make("One");
      const two = await make("Two");

      const mine = await tasks
        .claim({ taskId: one.id, profile: { kind: "agent", name: "scout" } })
        .orThrow();

      expect(mine.claim.holderId).toBe(alice.id);
      expect(mine.claim.profile).toEqual({ kind: "agent", name: "scout" });
      expect(mine.task.claim?.holderId).toBe(alice.id);

      await s.as(bob);
      expect(hint(await tasks.claim({ taskId: one.id }))).toBe("TASK_CLAIMED");

      const next = await tasks.claimNext({ organizationId: org }).orThrow();
      expect(next?.task.id).not.toBe(one.id);
      expect(next?.claim.holderId).toBe(bob.id);

      // Nothing is left that bob or alice could claim except finished work.
      await tasks.claimNext({ organizationId: org }).orThrow();
      await tasks.claimNext({ organizationId: org }).orThrow();
      expect(
        await tasks.claimNext({ organizationId: org }).orThrow(),
      ).toBeUndefined();

      await s.as(alice);

      const renewed = await tasks
        .renew({ taskId: one.id, token: mine.claim.token, lease: 300 })
        .orThrow();

      expect(renewed.epoch).toBe(mine.claim.epoch);
      expect(
        hint(await tasks.renew({ taskId: one.id, token: crypto.randomUUID() })),
      ).toBe("TASK_CLAIM_LOST");

      await s.service();
      await s.rows(
        "update better_supabase.task_claims set expires_at = now() - interval '1 second' where task_id = $1",
        [one.id],
      );
      await s.as(alice);

      expect(
        hint(await tasks.renew({ taskId: one.id, token: mine.claim.token })),
      ).toBe("TASK_CLAIM_LOST");
      expect(
        hint(await tasks.release({ taskId: one.id, token: mine.claim.token })),
      ).toBe("TASK_CLAIM_LOST");

      await s.service();

      const expired = await s.value<number>(
        "better_supabase.expire_task_claims()",
      );

      expect(expired).toBeGreaterThanOrEqual(1);
      expect(two.id).not.toBe(one.id);

      await s.as(bob);
      const taken = await tasks.claim({ taskId: one.id }).orThrow();
      expect(taken.claim.epoch).toBeGreaterThan(mine.claim.epoch);

      const delegated = await tasks
        .delegate({ taskId: one.id, toUserId: alice.id })
        .orThrow();

      expect(delegated.assigneeIds).toContain(alice.id);
      expect(delegated.claim).toBeUndefined();
    } finally {
      await env.s.close();
    }
  });

  it("creates a plan in one transaction and refuses a bad one whole", async () => {
    const env = await setup();

    try {
      const { s, tasks, org, team, owner } = env;
      await s.as(owner);

      const made = await tasks
        .createPlan({
          organizationId: org,
          plan: [
            { key: "epic", title: "Epic", teamId: team },
            { key: "a", title: "A", teamId: team, parentId: { key: "epic" } },
            {
              key: "b",
              title: "B",
              teamId: team,
              parentId: { key: "epic" },
              needs: [{ key: "a" }],
            },
          ],
        })
        .orThrow();

      expect(made.tasks.map((task) => task.title)).toEqual(["Epic", "A", "B"]);
      expect(made.tasks[2]?.parentId).toBe(made.keys["epic"]);
      expect(made.tasks[2]?.waitingOn).toBe(1);

      const before = await tasks.count({ organizationId: org }).orThrow();

      const bad = await tasks.createPlan({
        organizationId: org,
        plan: [
          { title: "Fine", teamId: team },
          { title: "Needs a ghost", teamId: team, needs: [{ key: "ghost" }] },
        ],
      });

      expect(hint(bad)).toBe("TASK_PLAN_INVALID");
      expect(await tasks.count({ organizationId: org }).orThrow()).toEqual(
        before,
      );

      const tooMany = await tasks.createPlan({
        organizationId: org,
        plan: Array.from({ length: 101 }, (_, i) => ({ title: `T${i}` })),
      });

      expect(hint(tooMany)).toBe("TASK_PLAN_TOO_LARGE");
    } finally {
      await env.s.close();
    }
  });

  it("keeps the close note, fails a task and orders a lane", async () => {
    const env = await setup();

    try {
      const { s, tasks, org, team, alice } = env;
      const stage = await stages(env);
      await s.as(alice);

      const make = (title: string) =>
        tasks
          .create({ organizationId: org, input: { title, teamId: team } })
          .orThrow();

      const a = await make("A");
      const b = await make("B");
      const c = await make("C");

      await tasks.complete({ taskId: a.id, note: "shipped" }).orThrow();
      const closed = await tasks.getTask(a.id).orThrow();
      expect(closed).toMatchObject({
        state: "completed",
        closeReason: "completed",
        closeNote: "shipped",
      });

      await tasks.fail({ taskId: b.id, note: "no network" }).orThrow();
      expect(await tasks.getTask(b.id).orThrow()).toMatchObject({
        state: "canceled",
        closeReason: "failed",
        closeNote: "no network",
      });

      await tasks.reopen({ taskId: b.id, stageId: stage("todo") }).orThrow();
      expect((await tasks.getTask(b.id).orThrow()).closeNote).toBeUndefined();

      await tasks
        .move({ taskId: c.id, stageId: stage("todo"), beforeId: b.id })
        .orThrow();

      const lane = await tasks
        .page({ organizationId: org, filters: { open: ["true"] }, limit: 50 })
        .orThrow();

      const ranks = new Map(lane.items.map((task) => [task.id, task.rank]));
      expect(ranks.get(c.id)! < ranks.get(b.id)!).toBe(true);

      const moved = await tasks
        .moveMany({
          moves: [
            { taskId: b.id, stageId: stage("todo"), beforeId: c.id },
            { taskId: c.id, stageId: crypto.randomUUID() },
          ],
        })
        .orThrow();

      expect(moved.accepted).toHaveLength(1);
      expect(moved.rejected).toHaveLength(1);

      const times = await tasks.stageTimes(b.id).orThrow();
      expect(times.length).toBeGreaterThan(0);
    } finally {
      await env.s.close();
    }
  });

  it("puts a task on hold and releases it", async () => {
    const env = await setup();

    try {
      const { s, tasks, org, team, alice, bob } = env;
      await stages(env);
      await s.as(alice);

      const task = await tasks
        .create({ organizationId: org, input: { title: "Ask", teamId: team } })
        .orThrow();

      const held = await tasks
        .hold({
          taskId: task.id,
          kind: "question",
          note: "Which region?",
          askUserIds: [bob.id],
        })
        .orThrow();

      expect(held.holdKind).toBe("question");
      expect(held.heldAt).toBeDefined();
      expect(hint(await tasks.claim({ taskId: task.id }))).toBe("TASK_HELD");

      const released = await tasks.releaseHold({ taskId: task.id }).orThrow();
      expect(released.heldAt).toBeUndefined();
    } finally {
      await env.s.close();
    }
  });
});
