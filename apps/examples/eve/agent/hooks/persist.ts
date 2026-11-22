import { persistSessions } from "better-supabase/eve";
import { createSupabaseWorld } from "better-supabase/workflow-sdk/world";
import { defineHook } from "eve/hooks";

// Wakes the session's sync job on the events that matter. The job
// (agent/lib/sync.ts) copies the session into ai_chats, ai_messages and
// ai_runs, so the chat history, search and memory recall see it. The World's
// triggers wake the same job, so a missed hook costs only a delay.
export default defineHook({
  events: persistSessions({ store: createSupabaseWorld().eveSessions }),
});
