import "server-only";
import { jobs } from "@/lib/jobs";

// The agent's inbox channel answers at /eve/v1/inbox; a failed post leaves
// the job on the queue for the next drain.
export const GET = jobs.drainRoute({
  secret: process.env["CRON_SECRET"],
  handlers: {
    inbox_bot: async (payload) => {
      const response = await fetch(
        `${process.env["APP_URL"] ?? ""}/eve/v1/inbox`,
        {
          method: "POST",
          headers: {
            authorization: `Bearer ${process.env["INBOX_BOT_SECRET"] ?? ""}`,
            "content-type": "application/json",
          },
          body: JSON.stringify({
            conversation_id: payload.conversation_id,
            message_id: payload.message_id,
          }),
        },
      );
      if (!response.ok) {
        throw new Error(`The inbox channel answered ${response.status}`);
      }
    },
  },
});
