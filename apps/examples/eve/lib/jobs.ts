import "server-only";
import { createJobs } from "better-supabase/blocks/jobs";
import { createPostgres } from "better-supabase/postgres";
import * as v from "valibot";

const postgres = createPostgres();

// The inbox module queues one inbox_bot job per contact message in a
// conversation in bot mode.
export const jobs = createJobs(postgres.admin, {
  inbox_bot: v.looseObject({
    conversation_id: v.string(),
    message_id: v.string(),
  }),
});
