// #region recipe:chat-with-history
"use client";

import type { UIMessage } from "ai";

import { useAssistant } from "better-supabase/ai-sdk/react";
import { useDurableAssistant } from "better-supabase/ai-sdk/workflow-react";
import { useExtracted } from "next-intl";
import { useRouter } from "next/navigation";
import { useState } from "react";

import { Button } from "@/components/ui/button";

import type { MessageBranch, ModelOption } from "../assistant-queries";

import { switchChatBranch } from "../assistant-actions";
import { ChatView } from "./chat-view";

const NO_MODELS: readonly ModelOption[] = [];
const NO_BRANCHES: readonly MessageBranch[] = [];

export type ChatMode = "standard" | "durable" | "research";

interface PanelProps {
  readonly id: string;
  readonly messages: UIMessage[];
  readonly streaming: boolean;
  readonly models: readonly ModelOption[];
  readonly model: string | undefined;
  readonly onModelChange: (model: string) => void;
  readonly branches: readonly MessageBranch[];
}

/**
 * The answer streams from the request; a reload picks it up from the stream
 * store.
 */
function StandardPanel({
  id,
  messages,
  models,
  model,
  onModelChange,
  branches,
}: PanelProps) {
  const router = useRouter();

  const chat = useAssistant({
    id,
    messages,
    ...(model === undefined ? {} : { model }),
    onFinish: () => {
      router.refresh();
    },
  });

  return (
    <ChatView
      id={id}
      chat={chat}
      models={models}
      {...(model === undefined ? {} : { model })}
      onModelChange={onModelChange}
      branches={branches}
      onSwitchBranch={(messageId) => {
        void switchChatBranch({ chatId: id, messageId }).then(() => {
          router.refresh();
        });
      }}
      uploads
      rating
    />
  );
}

/**
 * The answer runs as a workflow: it survives a closed tab and waits for
 * approvals.
 */
function DurablePanel({
  id,
  messages,
  streaming,
  agent,
}: PanelProps & { readonly agent: "assistant" | "research" }) {
  const router = useRouter();

  const chat = useDurableAssistant({
    id,
    api: "/api/chat/durable",
    body: { agent },
    messages,
    resume: streaming,
    onFinish: () => {
      router.refresh();
    },
  });

  return <ChatView id={id} chat={chat} uploads rating />;
}

/**
 * One chat. Standard answers stream from the request; Durable and Research
 * answers run as workflows, which need the AI Gateway key.
 */
export function AssistantChat({
  id,
  messages,
  streaming = false,
  initialMode = "standard",
  durableAvailable,
  models = NO_MODELS,
  initialModel,
  branches = NO_BRANCHES,
}: {
  id: string;
  messages: UIMessage[];
  streaming?: boolean;
  initialMode?: ChatMode;
  durableAvailable: boolean;
  models?: readonly ModelOption[];
  initialModel?: string | undefined;
  branches?: readonly MessageBranch[];
}) {
  const t = useExtracted("assistant");

  const [mode, setMode] = useState<ChatMode>(
    durableAvailable ? initialMode : "standard",
  );

  const modes: readonly { mode: ChatMode; label: string }[] = [
    { mode: "standard", label: t("Standard") },
    { mode: "durable", label: t("Durable") },
    { mode: "research", label: t("Research") },
  ];

  const [model, setModel] = useState<string | undefined>(
    initialModel ?? models[0]?.id,
  );

  const panel = {
    id,
    messages,
    streaming,
    models,
    model,
    onModelChange: setModel,
    branches,
  };

  return (
    <div className="flex flex-col gap-3">
      <fieldset className="flex flex-wrap items-center gap-2">
        <legend className="sr-only">{t("Answer mode")}</legend>
        {modes.map((entry) => (
          <Button
            key={entry.mode}
            size="sm"
            variant={mode === entry.mode ? "default" : "outline"}
            aria-pressed={mode === entry.mode}
            disabled={entry.mode !== "standard" && !durableAvailable}
            onClick={() => {
              setMode(entry.mode);
            }}
          >
            {entry.label}
          </Button>
        ))}
        {durableAvailable ? null : (
          <p className="text-xs text-muted-foreground">
            {t("Durable answers need AI_GATEWAY_API_KEY.")}
          </p>
        )}
      </fieldset>
      {mode === "standard" ? (
        <StandardPanel key="standard" {...panel} />
      ) : (
        <DurablePanel
          key={mode}
          {...panel}
          agent={mode === "research" ? "research" : "assistant"}
        />
      )}
    </div>
  );
}
// #endregion recipe:chat-with-history
