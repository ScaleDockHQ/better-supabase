"use client";

import { WifiOffIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useOffline } from "next/offline";

import { Alert, AlertDescription, AlertTitle } from "@/components/reui/alert";
import { cn } from "@/lib/utils";

/**
 * Shown while `useOffline()` reports no connection. Next.js keeps a failed
 * navigation, prefetch or Server Action pending and retries it when the
 * connection returns (`experimental.useOffline`), so the banner only explains
 * the wait.
 */
export function OfflineBanner({ className }: { className?: string }) {
  const offline = useOffline();
  const t = useExtracted("offline");

  if (!offline) {
    return null;
  }

  return (
    <output className={cn("block w-full", className)}>
      {/* The `output` wrapper is the polite status region; going offline is
          not urgent enough for the Alert's default `role="alert"`. */}
      <Alert variant="warning" role="none">
        <WifiOffIcon />
        <AlertTitle>{t("You are offline")}</AlertTitle>
        <AlertDescription>
          {t("Pending changes and pages load when you are back online.")}
        </AlertDescription>
      </Alert>
    </output>
  );
}
