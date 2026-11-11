"use client";

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
      lastAssistantMessageIsCompleteWithToolCalls(options),
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
