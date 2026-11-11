"use client";

import type { ReactNode } from "react";

import {
  ResizableHandle,
  ResizablePanel,
  ResizablePanelGroup,
} from "@/components/ui/resizable";

/**
 * The unibox frame: the queue on the left, the open conversation (its thread
 * and context) on the right. It stays mounted while the conversation changes,
 * so the queue keeps its filters, scroll and Realtime subscription.
 */
export function InboxShell({
  queue,
  children,
}: {
  queue: ReactNode;
  children: ReactNode;
}) {
  return (
    <div className="h-[calc(100svh-12rem)] min-h-128 overflow-hidden rounded-xl border">
      <ResizablePanelGroup orientation="horizontal" id="inbox-shell">
        <ResizablePanel
          id="queue"
          defaultSize="30%"
          minSize="22%"
          maxSize="45%"
        >
          {queue}
        </ResizablePanel>
        <ResizableHandle withHandle />
        <ResizablePanel id="conversation" defaultSize="70%" minSize="40%">
          {children}
        </ResizablePanel>
      </ResizablePanelGroup>
    </div>
  );
}
