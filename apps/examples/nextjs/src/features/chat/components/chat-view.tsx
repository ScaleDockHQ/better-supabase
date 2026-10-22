"use client";

import type { Message } from "better-supabase/blocks/messaging";

import { HashIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useState } from "react";

import { Card } from "@/components/ui/card";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";

import type { OpenChannel } from "./channel-sidebar";

import { ChannelSidebar } from "./channel-sidebar";
import { MessageList } from "./message-list";
import { ThreadPanel } from "./thread-panel";
import { ThreadSummary } from "./thread-summary";

export function ChatView() {
  const t = useExtracted("chat");
  const [channel, setChannel] = useState<OpenChannel | null>(null);
  const [thread, setThread] = useState<Message | null>(null);

  return (
    <div
      className={
        thread
          ? "grid h-[calc(100svh-12rem)] min-h-96 gap-4 lg:grid-cols-[16rem_1fr_20rem]"
          : "grid h-[calc(100svh-12rem)] min-h-96 gap-4 lg:grid-cols-[16rem_1fr]"
      }
    >
      <ChannelSidebar
        selected={channel?.id ?? null}
        onSelect={(next) => {
          setChannel(next);
          setThread(null);
        }}
      />
      {channel ? (
        <MessageList
          key={channel.id}
          conversationId={channel.id}
          name={channel.name}
          onOpenThread={setThread}
        />
      ) : (
        <Card size="sm">
          <Empty className="flex-1">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <HashIcon />
              </EmptyMedia>
              <EmptyTitle>{t("Pick a channel")}</EmptyTitle>
              <EmptyDescription>
                {t("Choose one on the left, or create a new one with +.")}
              </EmptyDescription>
            </EmptyHeader>
          </Empty>
        </Card>
      )}
      {thread ? (
        <div
          key={thread.id}
          className="grid min-h-0 grid-rows-[auto_minmax(0,1fr)] gap-4"
        >
          <ThreadSummary threadId={thread.id} />
          <ThreadPanel
            root={thread}
            onClose={() => {
              setThread(null);
            }}
          />
        </div>
      ) : null}
    </div>
  );
}
