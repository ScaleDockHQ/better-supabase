"use client";

import { RadioIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { lazy } from "react";

import { LazyOnIntent } from "@/components/lazy-on-intent";
import { Button } from "@/components/ui/button";

const ChannelSimulator = lazy(() =>
  import("./channel-simulator").then((mod) => ({
    default: mod.ChannelSimulator,
  })),
);

/** The simulator button. The dialog loads on the first hover, focus or click. */
export function ChannelSimulatorLazy() {
  const t = useExtracted("inbox");

  return (
    <span className="contents">
      <LazyOnIntent
        renderTrigger={(handlers) => (
          <Button
            variant="outline"
            size="sm"
            aria-haspopup="dialog"
            {...handlers}
          >
            <RadioIcon />
            {t("Simulate a message")}
          </Button>
        )}
      >
        <ChannelSimulator />
      </LazyOnIntent>
    </span>
  );
}
