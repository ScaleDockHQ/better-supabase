import "server-only";
import type { Message, Thread } from "chat";

import { sqlTransport } from "better-supabase/blocks/inbox";
import {
  conversationIdOf,
  createSupabaseState,
  inboxAdapter,
} from "better-supabase/chat-sdk";
import { Chat } from "chat";

import { env } from "@/env";
import { postgres } from "@/features/developer/postgres";
import { bsb } from "@/lib/supabase/server";

const USER_NAME = "Acme help";

/**
 * Answers a conversation the help bot handles when the in-app answer isn't
 * running (a visitor on the widget, an email): it subscribes, says a person
 * will follow up and hands the conversation to the team.
 */
async function handOff(thread: Thread, message: Message): Promise<void> {
  await thread.subscribe();
  await thread.post(
    "Thanks for the message. Someone from the team will reply here.",
  );
  await bsb
    .admin()
    .inbox.conversations.handoff(
      conversationIdOf(thread.id),
      `The help bot received: ${message.text.slice(0, 200)}`,
    )
    .orThrow();
}

function createInboxBot() {
  const connection = postgres();

  if (!connection) {
    return null;
  }

  const bot = new Chat({
    userName: USER_NAME,
    adapters: {
      inbox: inboxAdapter({
        inbox: bsb.admin().inbox,
        userName: USER_NAME,
        // The jobs drain posts inbox_bot jobs with the cron secret.
        verify: (request) =>
          env.CRON_SECRET !== undefined &&
          request.headers.get("authorization") === `Bearer ${env.CRON_SECRET}`,
      }),
    },
    state: createSupabaseState({ transport: sqlTransport(connection.admin) }),
  });

  bot.onDirectMessage(handOff);

  return bot;
}

type InboxBot = ReturnType<typeof createInboxBot>;

let instance: InboxBot | undefined;

/** The Chat SDK bot over the inbox; `null` without `WORKFLOW_POSTGRES_URL`. */
export function inboxBot(): InboxBot {
  instance ??= createInboxBot();

  return instance;
}
