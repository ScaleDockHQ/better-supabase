import { createSessionSync } from "better-supabase/eve";
import { createSupabaseWorld } from "better-supabase/workflow-sdk/world";
import { sessions } from "eve/server";

import { chats } from "./blocks";
import { postgres } from "./server";

// Reads each session through eve's own reader, from the stored cursor, and
// writes it into the chat tables. Every write is keyed by the event, so a
// pass that fails halfway runs again without duplicates.
export const sync = createSessionSync({
  store: createSupabaseWorld().eveSessions,
  chats,
  read: (sessionId, startIndex) =>
    sessions.attach(sessionId).stream({ startIndex, follow: false }),
  // A session's tenant is not in eve's principal: take the member's first
  // organization from your own tables.
  resolve: async ({ principal }) => {
    if (principal === undefined) {
      return;
    }

    const [row] = await postgres.admin.queryRaw<{ organization_id: string }>(
      "select organization_id from public.memberships where user_id = $1 limit 1",
      [principal.id],
    );

    return row === undefined
      ? undefined
      : {
          organizationId: row.organization_id,
          ownerId: principal.id,
          agentId: "acme-assistant",
        };
  },
});
