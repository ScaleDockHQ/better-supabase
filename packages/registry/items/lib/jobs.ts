import { createJobs } from "better-supabase/blocks/jobs";

import { postgres } from "@/lib/postgres";

/**
 * The job queues, one Standard Schema per queue for its payload. Add a
 * queue here and its handler in the drain route:
 * `createJobs(postgres.admin, { send_email: SendEmail })`.
 */
export const jobs = createJobs(postgres.admin, {});
