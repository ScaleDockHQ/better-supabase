import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import { loadAdminList } from "@/features/admin-lists/admin-list-load";
import { readPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { bsbShell } from "@/lib/supabase/server-shell";

import type { JobRow } from "./jobs-list";

import { JOBS_TAG } from "./jobs-cache";
import { jobList } from "./jobs-list";
import { JOBS_PERMISSION } from "./jobs-server";
import { getJobRun, jobSource, queueNames } from "./jobs-source";

/**
 * The first page of the organization's job runs with the count per status and
 * queue. `null` without an organization or `audit.read`. A failed read throws,
 * so it is never cached.
 */
export async function getJobRuns() {
  "use cache: private";
  const request = await bsbShell.cached();
  cacheTag(JOBS_TAG);
  const tenant = tenantOf(request.session);
  const permissions = await readPermissions(request);

  if (!tenant || !can(permissions, JOBS_PERMISSION)) {
    return null;
  }

  return loadAdminList({
    session: request.session,
    tenant,
    list: jobList,
    source: jobSource(await queueNames()),
    access: "admin",
    query: jobList.defaults,
  });
}

export interface JobRunDetail extends Omit<JobRow, "id"> {
  readonly payload: unknown;
}

/** One run with its payload; `null` when it isn't this organization's. */
export async function getJobRunDetail(
  queue: string,
  id: number,
): Promise<JobRunDetail | null> {
  "use cache: private";
  const request = await bsbShell.cached({ id: `${queue}:${String(id)}` });
  cacheTag(JOBS_TAG);
  const tenant = tenantOf(request.session);
  const permissions = await readPermissions(request);

  if (!tenant || !can(permissions, JOBS_PERMISSION)) {
    return null;
  }

  const row = await getJobRun(tenant, queue, id);

  if (!row) {
    return null;
  }

  return {
    queue: row.queue,
    messageId: Number(row.message_id),
    status: row.status,
    attempts: row.attempts,
    lastError: row.last_error,
    enqueuedAt: row.enqueued_at.toISOString(),
    finishedAt: row.finished_at?.toISOString() ?? null,
    payload: row.payload,
  };
}
