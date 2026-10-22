import { createBlocks, sqlTransport } from "better-supabase/blocks";
import { commentsBlock } from "better-supabase/blocks/comments";
import {
  createNotifications,
  notificationsBlock,
} from "better-supabase/blocks/notifications";
import { remindersBlock } from "better-supabase/blocks/reminders";
import { stateMachineBlock } from "better-supabase/blocks/state-machine";
import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { received, watching, workspace } from "./flow.ts";
import { NOTIFICATION_TYPES } from "./notification-types.ts";
import { projectManagement } from "./recipes.ts";
import { dbUrl, reachable, withRecipe } from "./stack.ts";

const live = await reachable();

const TASK =
  "insert into recipe_pm.tasks (organization_id, title) values ($1, 'Ship the beta') returning id";

describe.skipIf(!live)("project management recipe", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });

  afterAll(() => pool.end());

  it("moves a task through its workflow and notifies its watchers", async () => {
    await withRecipe(pool, projectManagement, async (s) => {
      const { owner, member, organizationId, subjectId } = await workspace(
        s,
        "task",
        TASK,
      );

      const watchers = await watching(s);

      const { comments, stateMachine } = createBlocks(
        { transport: sqlTransport(s.sql), tenant: organizationId },
        { comments: commentsBlock, stateMachine: stateMachineBlock },
      );

      await s.as(owner);
      await stateMachine
        .transition({ type: "task", id: subjectId }, "doing")
        .orThrow();
      await comments
        .create({ type: "task", id: subjectId }, { body: "Picked this up" })
        .orThrow();
      expect(
        await stateMachine.transition(
          { type: "task", id: subjectId },
          "todo",
          "blocked",
        ),
      ).toMatchObject({ ok: true });

      await watchers.relay();
      expect(await received(s, member, subjectId)).toEqual([
        "comment.posted",
        "subject.moved",
        "subject.moved",
      ]);
      await s.client.query("reset role");
      expect(
        await s.rows(
          "select from_status, to_status, reason from better_supabase.status_history where subject_id = $1 order by from_status",
          [subjectId],
        ),
      ).toEqual([
        { from_status: "doing", to_status: "todo", reason: "blocked" },
        { from_status: "todo", to_status: "doing", reason: null },
      ]);
    });
  });

  it("delivers a due-date reminder once, to its owner and the task's watchers", async () => {
    await withRecipe(pool, projectManagement, async (s) => {
      const { owner, member, organizationId, subjectId } = await workspace(
        s,
        "task",
        TASK,
      );

      const { reminders } = createBlocks(
        { transport: sqlTransport(s.sql), tenant: organizationId },
        {
          notifications: notificationsBlock.using((options) =>
            createNotifications({ ...options, types: NOTIFICATION_TYPES }),
          ),
          reminders: remindersBlock.with({ notification: "reminder.due" }),
        },
      );

      await s.as(owner);

      const reminder = await reminders
        .save({ type: "task", id: subjectId }, 60)
        .orThrow();

      await s.service();

      const delivery = {
        reminderId: reminder.id,
        occurrenceAt: "2026-10-20T09:00:00Z",
        organizationId,
        userId: owner.id,
        subject: { type: "task", id: subjectId },
      };

      expect(await reminders.deliver(delivery).orThrow()).toBe(true);
      expect(await reminders.deliver(delivery).orThrow()).toBe(false);

      expect(await received(s, owner, subjectId)).toEqual(["reminder.due"]);
      expect(await received(s, member, subjectId)).toEqual(["reminder.due"]);
    });
  });
});
