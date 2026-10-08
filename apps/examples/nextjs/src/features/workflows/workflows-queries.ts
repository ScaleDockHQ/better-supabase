import { tenantOf } from "better-supabase/next";
import "server-only";

import { blocks } from "@/lib/blocks";
import { bs } from "@/lib/supabase/server";

/** A schedule as plain data, so it crosses the server boundary. */
export interface ScheduleRow {
  readonly id: string;
  readonly name: string;
  readonly workflow: string;
  readonly cron: string;
  readonly nextRunAt: string;
  readonly paused: boolean;
}

/** The active organization's workflow schedules. */
export async function getSchedules(): Promise<readonly ScheduleRow[]> {
  "use cache: private";
  const { session, supabase } = await bs.cached();
  const tenant = tenantOf(session);
  if (!tenant) return [];
  const schedules = await blocks(supabase)
    .workflows.schedules.list(tenant)
    .orThrow();
  return schedules.map((schedule) => ({
    id: schedule.id,
    name: schedule.name,
    workflow: schedule.workflow,
    cron: schedule.cron,
    nextRunAt: schedule.nextRunAt.toString(),
    paused: schedule.paused,
  }));
}
