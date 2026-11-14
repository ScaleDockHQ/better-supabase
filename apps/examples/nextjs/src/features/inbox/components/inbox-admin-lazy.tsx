"use client";

import { MegaphoneIcon, WebhookIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { lazy } from "react";

import { LazyOnIntent } from "@/components/lazy-on-intent";
import { Button } from "@/components/ui/button";

const BroadcastDialog = lazy(() =>
  import("./broadcast-dialog").then((mod) => ({
    default: mod.BroadcastDialog,
  })),
);

const InboundEventsSheet = lazy(() =>
  import("./inbound-events-sheet").then((mod) => ({
    default: mod.InboundEventsSheet,
  })),
);

/**
 * The broadcast and webhook replay buttons; each loads on first intent. Each
 * sits in its own wrapper because `LazyOnIntent` opens the first
 * `[aria-haspopup]` in its parent.
 */
export function InboxAdminLazy() {
  const t = useExtracted("inbox");

  return (
    <>
      <span className="contents">
        <LazyOnIntent
          renderTrigger={(handlers) => (
            <Button
              variant="outline"
              size="sm"
              aria-haspopup="dialog"
              {...handlers}
            >
              <MegaphoneIcon />
              {t("Broadcast")}
            </Button>
          )}
        >
          <BroadcastDialog />
        </LazyOnIntent>
      </span>
      <span className="contents">
        <LazyOnIntent
          renderTrigger={(handlers) => (
            <Button
              variant="outline"
              size="sm"
              aria-haspopup="dialog"
              {...handlers}
            >
              <WebhookIcon />
              {t("Webhook events")}
            </Button>
          )}
        >
          <InboundEventsSheet />
        </LazyOnIntent>
      </span>
    </>
  );
}
