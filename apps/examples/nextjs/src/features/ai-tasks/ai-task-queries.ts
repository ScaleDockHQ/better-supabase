import "server-only";
import type { DbError } from "better-supabase";
import type { AiTaskRunStatus } from "better-supabase/blocks/ai-schedules";

import { tenantOf } from "better-supabase/next";

import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";
import { bsb } from "@/lib/supabase/server";

import { aiTasks } from "./ai-tasks-server";

export interface AiTaskRow {
  readonly id: string;
  readonly title: string;
  readonly prompt: string;
  readonly cron: string;
  readonly timezone: string;
  readonly enabled: boolean;
  /** ISO 8601. */
  readonly nextRunAt: string | undefined;
  readonly lastRun:
    | {
        readonly status: AiTaskRunStatus;
        /** ISO 8601. */
        readonly scheduledFor: string;
        readonly error: string | undefined;
      }
    | undefined;
}

/** A read that failed renders its error in the card, with a Retry. */
export type AiTasksRead =
  | { readonly ok: true; readonly tasks: readonly AiTaskRow[] }
  | { readonly ok: false; readonly error: DbError };

/**
 * The caller's scheduled tasks in the active organization, or every task with
 * `ai.admin`, newest first. Not cached: runs change their status.
 */
export async function getAiTasks(): Promise<AiTasksRead> {
  const [session, { supabase }] = await Promise.all([
    getSession(),
    bsb.context(),
  ]);

  const organizationId = tenantOf(session);

  if (!organizationId) {
    return { ok: true, tasks: [] };
  }

  const result = await aiTasks(supabase).list(organizationId, {
    all: can(session, "ai.admin"),
  });

  if (!result.ok) {
    return { ok: false, error: result.error };
  }

  return {
    ok: true,
    tasks: result.data.map((task) => ({
      id: task.id,
      title: task.title,
      prompt: task.prompt,
      cron: task.cron,
      timezone: task.timezone,
      enabled: task.enabled,
      nextRunAt: task.nextRunAt?.toString(),
      lastRun: task.lastRun && {
        status: task.lastRun.status,
        scheduledFor: task.lastRun.scheduledFor.toString(),
        error: task.lastRun.error,
      },
    })),
  };
}
