"use client";

import { MessageCircleQuestion } from "lucide-react";
import dynamic from "next/dynamic";
import { useState } from "react";

const loadPanel = () => import("./chat-panel");

/**
 * The chat client (`ai`, `@ai-sdk/react`) loads on first hover or click, so
 * it stays out of every docs page's bundle.
 */
const ChatPanel = dynamic(loadPanel, { ssr: false });

/** A floating panel that answers questions from the docs pages. */
export function AskAI() {
  const [open, setOpen] = useState(false);
  if (!open) {
    return (
      <button
        type="button"
        onPointerEnter={() => {
          void loadPanel();
        }}
        onFocus={() => {
          void loadPanel();
        }}
        onClick={() => {
          setOpen(true);
        }}
        className="bg-fd-background hover:bg-fd-accent fixed right-4 bottom-4 z-50 inline-flex items-center gap-2 rounded-full border px-4 py-2 text-sm shadow-lg"
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
