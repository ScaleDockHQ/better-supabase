"use client";

import { useExtracted } from "next-intl";
import { lazy, Suspense, useState } from "react";

import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";

const AssistantTourChat = lazy(() =>
  import("./assistant-tour-chat").then((mod) => ({
    default: mod.AssistantTourChat,
  })),
);

/**
 * `useChat` makes an id on mount and fails the prerender, so the tour mounts
 * after a click and its code loads then.
 */
export function AssistantTourLazy() {
  const t = useExtracted("assistant");
  const [started, setStarted] = useState(false);

  if (!started) {
    return (
      <Button
        size="sm"
        onClick={() => {
          setStarted(true);
        }}
      >
        {t("Start the scripted tour")}
      </Button>
    );
  }

  return (
    <Suspense fallback={<Skeleton className="min-h-96 w-full rounded-xl" />}>
      <AssistantTourChat />
    </Suspense>
  );
}
