import { createSupabaseState, inboxAdapter } from "better-supabase/chat-sdk";
import { routeInbox } from "better-supabase/eve";
import { chatSdkChannel } from "eve/channels/chat-sdk";

import { inbox, transport } from "../lib/blocks";

const bridge = chatSdkChannel({
  userName: "Acme assistant",
  adapters: {
    inbox: inboxAdapter({
      inbox,
      userName: "Acme assistant",
      // The jobs drain posts inbox_bot jobs here with the shared secret.
      verify: (request) =>
        process.env["INBOX_BOT_SECRET"] !== undefined &&
        request.headers.get("authorization") ===
          `Bearer ${process.env["INBOX_BOT_SECRET"]}`,
    }),
  },
  state: createSupabaseState({ transport }),
  // The inbox shows a reply once it is complete.
  streaming: false,
});

routeInbox(bridge, { inbox });

export default bridge.channel;
