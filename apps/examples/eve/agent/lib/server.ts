import { defineSupabase } from "better-supabase";
import { createQueue } from "better-supabase/blocks/queue";
import { eveAgentJob } from "better-supabase/eve";
import { createPostgres } from "better-supabase/postgres";
import { createServer } from "better-supabase/server";

import { schema } from "../../lib/supabase/generated";

const postgres = createPostgres();

// Tools run as the session's member through `forContext`, under row-level
// security, with the agent's `act` claim on the token.
export const bsb = createServer(defineSupabase(schema), { postgres });

// The every-minute eve schedule enqueues due schedules and drains this queue.
export const agentJobs = createQueue({
  sql: postgres.admin,
  queues: { eve: eveAgentJob },
});
