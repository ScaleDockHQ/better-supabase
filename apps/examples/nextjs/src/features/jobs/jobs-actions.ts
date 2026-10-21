"use server";

import { type Result, dbError, err, ok } from "better-supabase";
import * as v from "valibot";

import { requirePostgres, sqlResult } from "@/features/developer/postgres";
import { can } from "@/features/user/user-permissions";
import { refreshCaller } from "@/lib/refresh-caller";
import { bs } from "@/lib/supabase/server";

import { JOBS_PERMISSION, jobsOn, QUEUE_NAME, TEST_QUEUE } from "./jobs-server";

/**
 * Queues a job on `settings_test` with the caller and organization in its
 * context, so it shows up in the organization's runs.
 */
export const enqueueTestJob = bs.action(
  {
    requireTenant: true,
    authorize: (session) => can(session, JOBS_PERMISSION),
  },
  async (_input, { tenant, auth }): Promise<Result<number>> => {
    if (auth.kind !== "user") {
      return err(dbError("unauthorized", "Sign in to queue a job"));
    }

    const connection = requirePostgres();

    if (!connection.ok) {
      return connection;
    }

    const queued = await jobsOn(connection.data).enqueue(
      TEST_QUEUE,
      { message: "A test job from the jobs settings page" },
      { context: { actor: { kind: "user", id: auth.user.id }, tenant } },
    );

    if (queued.ok) {
      refreshCaller(auth);
    }

    return queued;
  },
);

/**
 * Queues a dead job again with its payload and context. It only replays a dead
 * letter whose recorded tenant is the caller's organization.
 */
export const retryJobRun = bs.action(
  {
    input: v.object({
      queue: v.pipe(v.string(), v.regex(QUEUE_NAME)),
      id: v.pipe(v.number(), v.integer(), v.minValue(1)),
    }),
    requireTenant: true,
    authorize: (session) => can(session, JOBS_PERMISSION),
  },
  async ({ queue, id }, { tenant, auth }): Promise<Result<number>> => {
    const connection = requirePostgres();

    if (!connection.ok) {
      return connection;
    }

    const replayed = await sqlResult(() =>
      connection.data.admin.queryRaw<{ id: string | null }>(
        `select better_supabase.replay_dead_job($1, msg_id) as id
         from pgmq."a_${queue}"
         where msg_id = $2 and message ? 'dead'
           and message #>> '{payload,context,tenant}' = $3`,
        [queue, id, tenant],
      ),
    );

    if (!replayed.ok) {
      return replayed;
    }

    const newId = replayed.data[0]?.id;

    if (newId === undefined || newId === null) {
      return err(dbError("not_found", "That job is not a failed run"));
    }

    refreshCaller(auth);

    return ok(Number(newId));
  },
);
