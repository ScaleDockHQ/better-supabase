import type { Adapter } from "chat";

import { parseMarkdown } from "chat";

import type { ConformanceReport } from "./conformance.ts";

import { conform, expect } from "./conformance.ts";

export interface TestChatAdapterOptions {
  /** A thread the adapter can post to, made for the test. */
  readonly threadId: string;
  /** A user `openDM` can open a conversation with; skips the check without it. */
  readonly dmUserId?: string;
}

/**
 * Runs the Chat SDK `Adapter` contract against `adapter` on a real thread:
 * thread ids round-trip, a posted message can be read back, parsed, edited and
 * deleted, and formatted text renders. The optional methods it has
 * (`fetchMessage`, `openDM`, `fetchChannelInfo`, `listThreads`,
 * `scheduleMessage`) get a check each.
 */
export function testChatAdapter(
  adapter: Adapter,
  options: TestChatAdapterOptions,
): Promise<ConformanceReport> {
  const { threadId, dmUserId } = options;
  const channelId = adapter.channelIdFromThreadId(threadId);

  return conform(`Adapter "${adapter.name}"`, [
    [
      "round-trips its thread ids",
      () => {
        expect(
          adapter.encodeThreadId(adapter.decodeThreadId(threadId)) === threadId,
          "encodeThreadId(decodeThreadId(id)) changed the id",
        );
      },
    ],
    [
      "posts, reads, edits and deletes a message",
      async () => {
        const posted = await adapter.postMessage(threadId, "conformance post");
        expect(posted.id.length > 0, "postMessage returned no id");
        expect(posted.threadId === threadId, "postMessage moved threads");
        expect(
          adapter.parseMessage(posted.raw).id === posted.id,
          "parseMessage gave another id",
        );
        const page = await adapter.fetchMessages(threadId, { limit: 50 });
        expect(
          page.messages.some((message) => message.id === posted.id),
          "fetchMessages missed the posted message",
        );
        await adapter.editMessage(threadId, posted.id, "conformance edit");

        if (adapter.fetchMessage) {
          const edited = await adapter.fetchMessage(threadId, posted.id);
          expect(
            edited?.text === "conformance edit",
            "fetchMessage did not return the edit",
          );
        }

        await adapter.deleteMessage(threadId, posted.id);
      },
    ],
    [
      "renders formatted text",
      () => {
        expect(
          adapter.renderFormatted(parseMarkdown("**bold**")).includes("bold"),
          "renderFormatted dropped the text",
        );
      },
    ],
    adapter.openDM !== undefined &&
      dmUserId !== undefined && [
        "opens a DM it can post to",
        async () => {
          const dm = await adapter.openDM?.(dmUserId);
          expect(typeof dm === "string", "openDM returned no thread id");
          adapter.decodeThreadId(dm);
          expect(adapter.isDM?.(dm) ?? true, "the DM thread is not a DM");
        },
      ],
    adapter.fetchChannelInfo !== undefined && [
      "describes the thread's channel",
      async () => {
        const info = await adapter.fetchChannelInfo?.(channelId);
        expect(info?.id === channelId, "fetchChannelInfo named another id");
      },
    ],
    adapter.listThreads !== undefined && [
      "lists the channel's threads",
      async () => {
        const page = await adapter.listThreads?.(channelId, { limit: 5 });
        expect(page !== undefined, "listThreads returned nothing");
        expect(page.threads.length <= 5, "listThreads ignored the limit");

        for (const thread of page.threads) {
          expect(
            thread.rootMessage.threadId === thread.id,
            "a root message names another thread",
          );
        }
      },
    ],
    adapter.scheduleMessage !== undefined && [
      "schedules a message and cancels it",
      async () => {
        const postAt = new Date(Date.now() + 3_600_000);

        const scheduled = await adapter.scheduleMessage?.(
          threadId,
          "conformance schedule",
          { postAt },
        );

        expect(scheduled !== undefined, "scheduleMessage returned nothing");
        expect(
          scheduled.postAt.getTime() === postAt.getTime(),
          "scheduleMessage moved postAt",
        );
        expect(
          scheduled.scheduledMessageId.length > 0,
          "scheduleMessage returned no id",
        );
        await scheduled.cancel();
      },
    ],
  ]);
}
