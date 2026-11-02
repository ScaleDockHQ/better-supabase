"use server";

import { ok } from "better-supabase";
import { refresh } from "next/cache";
import * as v from "valibot";

import { bsb } from "@/lib/supabase/server";

import { aiTasks } from "./ai-tasks-server";

/** Schedules a weekday summary for the caller, so the queue has a row to show. */
export const scheduleSampleTask = bsb.action(
  {
    input: v.object({}),
    requireTenant: true,
    permission: "ai_schedules.write",
  },
  async (_input, { tenant, supabase }) => {
    const created = await aiTasks(supabase).create({
      organizationId: tenant,
      task: {
        title: "Weekday customer summary",
        prompt: "Summarize the customers added since yesterday.",
        cron: "0 9 * * 1-5",
        timezone: "UTC",
      },
    });

    if (!created.ok) {
      return created;
    }

    refresh();

    return ok(created.data.id);
  },
);

/** Turns a task off or back on; a resumed task runs at its next occurrence. */
export const setAiTaskEnabled = bsb.action(
  {
    input: v.object({ id: v.pipe(v.string(), v.uuid()), enabled: v.boolean() }),
    requireTenant: true,
    permission: "ai_schedules.write",
  },
  async ({ id, enabled }, { tenant, supabase }) => {
    const tasks = aiTasks(supabase);

    const saved = enabled
      ? await tasks.resume({ organizationId: tenant, taskId: id })
      : await tasks.pause({ organizationId: tenant, taskId: id });

    if (!saved.ok) {
      return saved;
    }

    refresh();

    return ok(saved.data.enabled);
  },
);
