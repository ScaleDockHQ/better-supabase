import { persistSessions } from "better-supabase/eve";
import { defineHook } from "eve/hooks";

import { chats } from "../lib/blocks";

// Copies every member session into ai_chats, ai_messages and ai_runs, so the
// chat history, search and memory recall see it.
export default defineHook({
  events: persistSessions({ chats, agentId: "acme-assistant" }),
});
