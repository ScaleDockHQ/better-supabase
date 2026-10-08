"use client";

import type { UIMessage } from "ai";

import { useAssistant } from "better-supabase/ai-sdk/react";
import { ArrowUpIcon, SquareIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useRouter } from "next/navigation";
import { useState } from "react";

import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";

const textOf = (message: UIMessage): string =>
  message.parts
    .flatMap((part) => (part.type === "text" ? [part.text] : []))
    .join("");

/**
 * One chat on `useAssistant`: the server keeps the history, so a reload
 * shows the stored messages and picks up an answer that is still streaming.
 */
export function AssistantChat({
  id,
  messages,
}: {
  id: string;
  messages: UIMessage[];
}) {
  const t = useExtracted("assistant");
  const router = useRouter();
  const [input, setInput] = useState("");
  const chat = useAssistant({
    id,
    messages,
    onFinish: () => {
      router.refresh();
    },
  });
  const busy = chat.status === "submitted" || chat.status === "streaming";

  const send = () => {
    const text = input.trim();
    if (text === "" || busy) return;
    setInput("");
    void chat.sendMessage({ text });
  };

  return (
    <div className="flex min-h-96 flex-col gap-4 rounded-xl border p-4">
      <ol className="flex flex-1 flex-col gap-3" aria-live="polite">
        {chat.messages.map((message) => (
          <li
            key={message.id}
            className={
              message.role === "user"
                ? "bg-primary text-primary-foreground max-w-4/5 self-end rounded-xl px-3 py-2 text-sm"
                : "bg-muted max-w-4/5 self-start rounded-xl px-3 py-2 text-sm"
            }
          >
            <p className="whitespace-pre-wrap">{textOf(message)}</p>
          </li>
        ))}
      </ol>
      {chat.error ? (
        <p role="alert" className="text-destructive text-sm">
          {t("The answer failed. Try again.")}
        </p>
      ) : null}
      <form
        className="flex items-end gap-2"
        onSubmit={(event) => {
          event.preventDefault();
          send();
        }}
      >
        <Textarea
          value={input}
          onChange={(event) => {
            setInput(event.target.value);
          }}
          onKeyDown={(event) => {
            if (event.key === "Enter" && !event.shiftKey) {
              event.preventDefault();
              send();
            }
          }}
          placeholder={t("Ask anything")}
          aria-label={t("Message")}
          rows={2}
        />
        {busy ? (
          <Button
            type="button"
            size="icon"
            variant="outline"
            onClick={() => {
              void chat.stop();
            }}
            aria-label={t("Stop")}
          >
            <SquareIcon />
          </Button>
        ) : (
          <Button type="submit" size="icon" aria-label={t("Send")}>
            <ArrowUpIcon />
          </Button>
        )}
      </form>
    </div>
  );
}
