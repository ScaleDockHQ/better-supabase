import { createQueue } from "better-supabase/blocks/queue";

import { postgres } from "@/lib/postgres";

/**
 * The job queues, one Standard Schema per queue for its payload. Add a queue
 * here and its handler in the drain route: `createQueue({ sql: postgres.admin,
 * queues: { send_email: SendEmail } })`.
 */
export const jobs = createQueue({ sql: postgres.admin, queues: {} });
