"use client";

import type { ComponentProps } from "react";

import { lazy, Suspense } from "react";

import { Skeleton } from "@/components/ui/skeleton";

const AssistantChat = lazy(() =>
  import("./assistant-chat").then((mod) => ({ default: mod.AssistantChat })),
);

/**
 * The chat panel. `ai`, `@ai-sdk/react`, the gateway client and the Workflow
 * transport load after the first paint: the server HTML is on screen first and
 * the panel hydrates once its code arrives.
 */
export function AssistantChatLazy(props: ComponentProps<typeof AssistantChat>) {
  return (
    <Suspense fallback={<Skeleton className="min-h-96 w-full rounded-xl" />}>
      <AssistantChat {...props} />
    </Suspense>
  );
}
