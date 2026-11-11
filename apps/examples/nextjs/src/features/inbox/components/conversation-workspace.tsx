"use client";

import type { ReactNode } from "react";

import {
  ResizableHandle,
  ResizablePanel,
  ResizablePanelGroup,
} from "@/components/ui/resizable";

import { ConversationPanel } from "./conversation-panel";

/**
 * The thread and the context pane of one conversation. The context is rendered
 * on the server and arrives as a slot; the thread is a client component that
 * stays live over Realtime.
 */
export function ConversationWorkspace({
  conversationId,
  context,
}: {
  conversationId: string;
  context: ReactNode;
}) {
  return (
    <ResizablePanelGroup orientation="horizontal" id="inbox-conversation">
      <ResizablePanel id="thread" defaultSize="68%" minSize="40%">
        <ConversationPanel
          key={conversationId}
          conversationId={conversationId}
        />
      </ResizablePanel>
      <ResizableHandle withHandle />
      <ResizablePanel id="context" defaultSize="32%" minSize="20%">
        {context}
      </ResizablePanel>
    </ResizablePanelGroup>
  );
}
