import "server-only";
import { createInbox } from "better-supabase/blocks/inbox";
import { rpcTransport } from "better-supabase/blocks/organizations";
import * as v from "valibot";

import {
  assistant,
  assistantContext,
} from "@/features/assistant/assistant-server";
import { bs } from "@/lib/supabase/server";

/** `sql.modules.inbox.api` in better-supabase.config.ts. */
const API_SCHEMA = "api";
const BOT = "assistant";

type Client = Parameters<typeof assistantContext>[0];

const TextDelta = v.object({
  type: v.literal("text-delta"),
  delta: v.string(),
});

/** The inbox as the service role: the bot writes as `bot`, not as the visitor. */
function serviceInbox() {
  return createInbox({
    transport: rpcTransport(bs.admin().$client, { schema: API_SCHEMA }),
    schema: API_SCHEMA,
  });
}

/** The text the assistant streamed, read from its UI message stream (SSE). */
async function streamedText(response: Response): Promise<string> {
  let text = "";
  for (const line of (await response.text()).split("\n")) {
    if (!line.startsWith("data: ")) continue;
    try {
      const part = v.safeParse(TextDelta, JSON.parse(line.slice(6)));
      if (part.success) text += part.output.delta;
    } catch {
      // `data: [DONE]` ends the stream and is not JSON.
    }
  }
  return text.trim();
}

/**
 * Answers the visitor's Help message with the `/assistant` setup, in the
 * visitor's own chat (its id is the conversation's), then posts the answer
 * as the bot. A handoff to staff while it writes drops the answer.
 */
export async function answerHelp(
  supabase: Client,
  userId: string,
  conversationId: string,
  message: string,
): Promise<void> {
  const inbox = serviceInbox();
  const conversation = await inbox.conversations.get(conversationId);
  if (!conversation.ok || conversation.data?.botMode !== "bot") return;
  await inbox.conversations.typing(conversationId, true, BOT);
  try {
    const response = await assistant().respond(
      new Request("https://help.internal/api/chat", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          id: conversationId,
          message: {
            id: crypto.randomUUID(),
            role: "user",
            parts: [{ type: "text", text: message }],
          },
        }),
      }),
      assistantContext(supabase, userId, conversation.data.tenant),
    );
    if (!response.ok) return;
    const answer = await streamedText(response);
    const current = await inbox.conversations.get(conversationId);
    if (answer === "" || !current.ok || current.data?.botMode !== "bot") return;
    await inbox.messages.send(conversationId, {
      body: answer,
      format: "markdown",
      authorType: "bot",
    });
  } finally {
    await inbox.conversations.typing(conversationId, false, BOT);
  }
}
