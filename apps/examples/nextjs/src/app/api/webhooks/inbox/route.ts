import { after } from "next/server";

import { inboxBot } from "@/features/inbox/inbox-bot";

/**
 * Takes an `inbox_bot` job from the jobs drain and runs the Chat SDK bot after
 * the response, so the drain isn't held while the bot answers.
 */
export async function POST(request: Request): Promise<Response> {
  const bot = inboxBot();

  if (!bot) {
    return new Response("Set WORKFLOW_POSTGRES_URL to run the inbox bot", {
      status: 503,
    });
  }

  return bot.webhooks.inbox(request, {
    waitUntil: (task) => {
      after(() => task);
    },
  });
}
