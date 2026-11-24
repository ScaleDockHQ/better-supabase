"use client";

import { SparklesIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { lazy } from "react";

import { LazyOnIntent } from "@/components/lazy-on-intent";
import { Button } from "@/components/ui/button";

const AssistantSlot = lazy(() =>
  import("./assistant-slot").then((mod) => ({ default: mod.AssistantSlot })),
);

/** The Assistant button of the header; the panel loads on the first intent. */
export function AssistantSlotLazy() {
  const t = useExtracted("assistant");

  return (
    <LazyOnIntent
      renderTrigger={(handlers) => (
        <Button
          variant="ghost"
          size="sm"
          aria-label={t("Assistant")}
          aria-haspopup="dialog"
          {...handlers}
        >
          <SparklesIcon />
          <span className="hidden sm:inline">{t("Assistant")}</span>
        </Button>
      )}
    >
      <AssistantSlot />
    </LazyOnIntent>
  );
}
