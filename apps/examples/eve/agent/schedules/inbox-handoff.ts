import { inboxHandoff } from "better-supabase/eve";
import { defineSchedule } from "eve/schedules";
import * as v from "valibot";

import eve from "../channels/eve";
import { inbox } from "../lib/blocks";

// Stores each event's message as the contact's and starts an eve session for
// the conversations in bot mode. The session's principal is the contact in
// that conversation (`inboxPrincipal`); its tools run as a service user
// (`inboxRunAs`).
const handoff = inboxHandoff({
  inbox,
  channel: eve,
  parsers: {
    webhook: (event) => {
      const body = v.parse(
        v.object({
          thread: v.string(),
          from: v.optional(v.string()),
          text: v.string(),
        }),
        JSON.parse(event.body),
      );

      return {
        threadId: body.thread,
        contact: { externalId: body.from ?? body.thread },
        text: body.text,
        externalId: event.externalId ?? undefined,
      };
    },
  },
});

// Every minute: hand the stored webhook events to eve. A reply is written by
// the session sync (`inboxReplies`, in agent/lib/sync.ts), as a bot message or
// as an ai draft for staff to review.
export default defineSchedule({
  cron: "* * * * *",
  run: (args) => {
    args.waitUntil(handoff(args));
  },
});
