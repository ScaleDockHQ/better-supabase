"use client";

import { useChat } from "@ai-sdk/react";
import { DefaultChatTransport, type UIMessage } from "ai";
import { MessageCircleQuestion, X } from "lucide-react";
import { type SubmitEvent, useState } from "react";

const transport = new DefaultChatTransport({ api: "/docs/api/chat" });

function messageText(message: UIMessage): string {
  return message.parts
    .map((part) => (part.type === "text" ? part.text : ""))
    .join("");
}

/** A floating panel that answers questions from the docs pages. */
export function AskAI() {
  const [open, setOpen] = useState(false);
  if (!open) {
    return (
      <button
        type="button"
        onClick={() => {
          setOpen(true);
        }}
        className="fixed right-4 bottom-4 z-50 inline-flex items-center gap-2 rounded-full border bg-fd-background px-4 py-2 text-sm shadow-lg hover:bg-fd-accent"
      >
        <MessageCircleQuestion className="size-4" aria-hidden />
        Ask AI
      </button>
    );
  }
  return (
    <ChatPanel
      onClose={() => {
        setOpen(false);
      }}
    />
  );
}

/** `useChat` creates a random chat id, so it mounts only once the panel opens. */
function ChatPanel({ onClose }: { onClose: () => void }) {
  const [input, setInput] = useState("");
  const { messages, sendMessage, status, error } = useChat({ transport });
  const busy = status === "submitted" || status === "streaming";

  function submit(event: SubmitEvent<HTMLFormElement>) {
    event.preventDefault();
    const text = input.trim();
    if (text === "" || busy) {
      return;
    }
    void sendMessage({ text });
    setInput("");
  }

  return (
    <section
      aria-label="Ask AI"
      className="fixed right-4 bottom-4 z-50 flex max-h-[70vh] w-[min(28rem,calc(100vw-2rem))] flex-col rounded-xl border bg-fd-background shadow-xl"
    >
      <header className="flex items-center justify-between border-b px-4 py-2">
        <h2 className="text-sm font-medium">Ask AI about the docs</h2>
        <button
          type="button"
          aria-label="Close Ask AI"
          onClick={onClose}
          className="rounded p-1 hover:bg-fd-accent"
        >
          <X className="size-4" aria-hidden />
        </button>
      </header>
      <ol className="flex-1 space-y-3 overflow-y-auto px-4 py-3 text-sm">
        {messages.map((message) => (
          <li
            key={message.id}
            className={
              message.role === "user"
                ? "ml-8 rounded-lg bg-fd-accent px-3 py-2"
                : "whitespace-pre-wrap"
            }
          >
            {messageText(message)}
          </li>
        ))}
        {error === undefined ? null : (
          <li className="text-fd-muted-foreground">
            Ask AI could not answer. Try the search, or ask again later.
          </li>
        )}
      </ol>
      <form onSubmit={submit} className="flex gap-2 border-t p-3">
        <input
          value={input}
          onChange={(event) => {
            setInput(event.currentTarget.value);
          }}
          placeholder="How do I verify a token?"
          aria-label="Question"
          className="flex-1 rounded-md border bg-transparent px-3 py-1.5 text-sm"
        />
        <button
          type="submit"
          disabled={busy}
          className="rounded-md bg-fd-primary px-3 py-1.5 text-sm text-fd-primary-foreground disabled:opacity-50"
        >
          Ask
        </button>
      </form>
      <p className="px-4 pb-3 text-xs text-fd-muted-foreground">
        Answers come from these docs and can be wrong.
      </p>
    </section>
  );
}
