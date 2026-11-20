import { createSupabase } from "better-supabase";
import { createQueue, sqlScheduler } from "better-supabase/blocks/queue";
import {
  eveAgentJob,
  eveScheduleRun,
  queueScheduleProvider,
  validateExpression,
} from "better-supabase/eve";
import { createPostgres } from "better-supabase/postgres";
import { createServer } from "better-supabase/server";
import * as v from "valibot";

import { schema } from "../../lib/supabase/generated-schema";
import { aiSchedules } from "./blocks";

export const postgres = createPostgres();

// Tools run as the session's member through `forContext`, under row-level
// security, with the agent's `act` claim on the token.
export const bsb = createServer(createSupabase(schema), { postgres });

// The every-minute eve schedule enqueues due schedules and drains this queue.
export const agentJobs = createQueue({
  sql: postgres.admin,
  queues: { eve: eveAgentJob },
});

// eve's dynamic schedules need a scheduler that keeps each schedule's payload,
// time zone and tenant: the drain scheduler (`blocks.queue.options.scheduler:
// "drain"`). The fixture installs pg_cron, which keeps none of them.
const scheduler = sqlScheduler(postgres.admin, { mode: "drain" });

const MemberScope = v.tuple([v.string(), v.string()]);

export const memberSchedules = queueScheduleProvider({
  scheduler,
  // agent/schedules/requests.ts scopes each schedule to [tenant, member].
  tenantOf: (scope) => v.parse(MemberScope, scope)[0],
  // Members' schedules also show up in the ai-schedules tables with each
  // occurrence's status, under the source `eve`. The dispatcher in
  // agent/schedules/tasks.ts skips them: eve fires them.
  mirror: { schedules: aiSchedules },
  // No more often than every five minutes, and no time that has passed.
  validateExpression: (expression) => {
    validateExpression(expression, { minIntervalMs: 5 * 60_000 });
  },
});

export const scheduleRuns = createQueue({
  sql: postgres.admin,
  scheduler,
  queues: { eve_schedules: eveScheduleRun },
});
