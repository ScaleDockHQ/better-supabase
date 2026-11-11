import { tagFor } from "better-supabase/next";

/**
 * Every server read of the inbox carries this tag. The thread and the queue
 * stay current over Realtime, so only the context beside a thread (the
 * contact's earlier conversations) is cached.
 */
export const INBOX_TAG = tagFor("inbox");
