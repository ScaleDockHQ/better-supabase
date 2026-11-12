"use client";

import type { UIMessage } from "ai";

import { useChat } from "@ai-sdk/react";
import {
  lastAssistantMessageIsCompleteWithApprovalResponses,
  lastAssistantMessageIsCompleteWithToolCalls,
} from "ai";
import { useExtracted } from "next-intl";
import { useMemo } from "react";

import { Button } from "@/components/ui/button";

import { assistantTour } from "../assistant-tour";
import { ChatView } from "./chat-view";

/**
 * The scripted `searchKnowledge` call arrives with its output, so the SDK's
 * tool-call check would send the next turn on its own. Only the answer to the
 * clarifying questions continues the script by itself.
 */
const questionsAnswered = (options: { messages: UIMessage[] }): boolean =>
  lastAssistantMessageIsCompleteWithToolCalls(options) &&
  options.messages
    .at(-1)
    ?.parts.some(
      (part) =>
        part.type === "dynamic-tool" &&
        part.toolName === "askQuestions" &&
        part.state === "output-available",
    ) === true;

/**
 * The tour: the chat view over a scripted transport. It uses `useChat`
 * directly, so nothing is stored and no model is called.
 */
export function AssistantTourChat() {
  const t = useExtracted("assistant");
  const script = useMemo(() => assistantTour(), []);
  const transport = useMemo(() => script.transport({ delayMs: 20 }), [script]);

  const chat = useChat({
    transport,
    sendAutomaticallyWhen: (options) =>
      lastAssistantMessageIsCompleteWithApprovalResponses(options) ||
      questionsAnswered(options),
  });

  const next = script.next(chat.messages);
  const busy = chat.status === "submitted" || chat.status === "streaming";

  return (
    <div className="flex flex-col gap-3">
      <ChatView id="tour" chat={{ ...chat, stop: () => chat.stop() }} />
      {next === null ? null : (
        <div>
          <Button
            size="sm"
            variant="outline"
            disabled={busy}
            onClick={() => {
              void chat.sendMessage(next);
            }}
          >
            {t("Send the next scripted message")}
          </Button>
        </div>
      )}
    </div>
  );
}
