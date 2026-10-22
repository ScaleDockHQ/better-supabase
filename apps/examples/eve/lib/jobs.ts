import "server-only";
import { createQueue } from "better-supabase/blocks/queue";
import { createPostgres } from "better-supabase/postgres";
import * as v from "valibot";

const postgres = createPostgres();

// The inbox module queues one inbox_bot job per contact message in a
// conversation in bot mode.
export const jobs = createQueue({
  sql: postgres.admin,
  queues: {
    inbox_bot: v.looseObject({
      conversation_id: v.string(),
      message_id: v.string(),
    }),
  },
});
