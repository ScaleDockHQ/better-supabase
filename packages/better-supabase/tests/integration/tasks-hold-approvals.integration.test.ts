import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";
import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

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
  "approvals",
  "tasks",
];

const DECIDE = "better_supabase.decide_approval($1, $2, $3)";

const layout = (
  onReject: "cancel" | "keep",
  hold: Record<string, unknown> = {},
  approval: Record<string, unknown> = {},
): BlockSqlLayout => ({
  subjects: withBlockSubjects({}, ["tasks"], {}),
  modules: {
    tasks: {
      tables: { projects: "work_projects" },
      options: { hold: { ...hold, approval: { onReject, ...approval } } },
    },
  },
});

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

describe.skipIf(!live)("task hold approvals", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  const run = async (
    onReject: "cancel" | "keep",
    check: (env: {
      s: BlockSession;
      tasks: ReturnType<typeof createTasks>;
      org: string;
      owner: Awaited<ReturnType<BlockSession["user"]>>;
      alice: Awaited<ReturnType<BlockSession["user"]>>;
      taskId: string;
      approvalId: () => Promise<string>;
    }) => Promise<void>,
    hold: Record<string, unknown> = {},
    approval: Record<string, unknown> = {},
    kind = "review",
  ): Promise<void> => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const alice = await s.user("alice");
      await s.install(MODULES, layout(onReject, hold, approval));
      const org = await s.organization(owner, { member: alice });
      const transport = sqlTransport(s.sql);
      const tasks = createTasks({ transport });
      const team = crypto.randomUUID();

      await s.as(alice);
      // The first task creates the team's pipeline.
      await tasks
        .create({ organizationId: org, input: { title: "seed", teamId: team } })
        .orThrow();

      const task = await tasks
        .create({ organizationId: org, input: { title: "Held", teamId: team } })
        .orThrow();

      await tasks
        .hold({ taskId: task.id, kind, note: "Please check" })
        .orThrow();

      const approvalId = async (): Promise<string> => {
        await s.service();

        const [row] = await s.rows<{ id: string }>(
          `select id from better_supabase.approval_requests
           where subject_type = 'task_hold' and subject_id = $1`,
          [task.id],
        );

        return row?.id ?? "";
      };

      await check({ s, tasks, org, owner, alice, taskId: task.id, approvalId });
    } finally {
      await s.close();
    }
  };

  it("releases the task when the hold is approved", async () => {
    await run(
      "cancel",
      async ({ s, tasks, owner, alice, taskId, approvalId }) => {
        const id = await approvalId();

        expect(id).not.toBe("");

        // A member without the manage permission can't decide.
        await s.as(alice);
        expect(await s.hint(DECIDE, [id, "approved", null])).toBe(
          "APPROVAL_FORBIDDEN",
        );

        await s.as(owner);
        expect(await s.value(DECIDE, [id, "approved", "ok"])).toMatchObject({
          status: "approved",
        });

        const task = await tasks.get(taskId).orThrow();

        expect(task?.heldAt).toBeUndefined();
        expect(task?.closedAt).toBeUndefined();
        expect(hint(await tasks.releaseHold({ taskId }))).toBe("TASK_NOT_HELD");
      },
    );
  });

  it("cancels the task when the hold is rejected", async () => {
    await run("cancel", async ({ s, tasks, owner, taskId, approvalId }) => {
      const id = await approvalId();

      await s.as(owner);
      await s.value(DECIDE, [id, "rejected", "no"]);

      const task = await tasks.get(taskId).orThrow();

      expect(task?.heldAt).toBeUndefined();
      expect(task?.closedAt).toBeDefined();
    });
  });

  it("leaves the task on hold with onReject keep", async () => {
    await run("keep", async ({ s, tasks, owner, taskId, approvalId }) => {
      const id = await approvalId();

      await s.as(owner);
      await s.value(DECIDE, [id, "rejected", "not yet"]);

      const task = await tasks.get(taskId).orThrow();

      expect(task?.heldAt).toBeDefined();
      expect(task?.closedAt).toBeUndefined();
    });
  });

  it("refuses a decision once the task is no longer on hold", async () => {
    await run(
      "cancel",
      async ({ s, tasks, owner, alice, taskId, approvalId }) => {
        const id = await approvalId();

        await s.as(alice);
        await tasks.releaseHold({ taskId }).orThrow();

        await s.as(owner);
        expect(await s.hint(DECIDE, [id, "approved", null])).not.toBe("ok");
      },
    );
  });

  const status = async (s: BlockSession, taskId: string): Promise<string> => {
    await s.service();

    const [row] = await s.rows<{ status: string }>(
      `select status from better_supabase.approval_requests
       where subject_type = 'task_hold' and subject_id = $1`,
      [taskId],
    );

    return row?.status ?? "none";
  };

  it("cancels the pending request when the hold is released", async () => {
    await run("cancel", async ({ s, tasks, alice, taskId }) => {
      expect(await status(s, taskId)).toBe("pending");

      await s.as(alice);
      await tasks.releaseHold({ taskId }).orThrow();

      expect(await status(s, taskId)).toBe("cancelled");
    });
  });

  it("cancels the pending request when the task is closed", async () => {
    await run("cancel", async ({ s, tasks, alice, taskId }) => {
      await s.as(alice);
      await tasks.cancel({ taskId }).orThrow();

      expect(await status(s, taskId)).toBe("cancelled");
    });
  });

  it("limits hold kinds, and files an approval only for the listed ones", async () => {
    await run(
      "cancel",
      async ({ s, tasks, org, alice, taskId }) => {
        // "input" is allowed but not approvable: no request is filed.
        expect(await status(s, taskId)).toBe("none");

        await s.as(alice);
        await tasks.releaseHold({ taskId }).orThrow();

        expect(
          hint(await tasks.hold({ taskId, kind: "other", note: "x" })),
        ).toBe("TASK_HOLD_INVALID");

        expect(org).toBeDefined();
      },
      { kinds: ["review", "input"] },
      { kinds: ["review"] },
      "input",
    );
  });

  it("refuses an approval kind the hold does not allow", async () => {
    const s = await BlockSession.open(pool);

    try {
      await expect(
        s.install(
          MODULES,
          layout("cancel", { kinds: ["input"] }, { kinds: ["review"] }),
        ),
      ).rejects.toThrow(/does not allow/);
    } finally {
      await s.close();
    }
  });
});
