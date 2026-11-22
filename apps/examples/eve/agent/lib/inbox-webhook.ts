import type { EveInboxConnection } from "better-supabase/eve";

import { inboxConnectionWebhook } from "better-supabase/eve";

import { inbox } from "./blocks";

// One row per connected channel, by the id in the webhook path. The secret is
// the connection's own, so a request for one connection never passes as
// another's.
const connections = new Map<string, EveInboxConnection & { secret: string }>();

export const connect = (
  id: string,
  connection: Omit<EveInboxConnection, "verify" | "adapter"> & {
    secret: string;
  },
): void => {
  connections.set(id, {
    ...connection,
    adapter: "webhook",
    verify: (request) =>
      request.headers.get("x-signature") === connection.secret,
  });
};

// POST /api/inbox/webhooks/<connection>
export const receive = inboxConnectionWebhook({
  inbox,
  connection: (id) => connections.get(id),
});
