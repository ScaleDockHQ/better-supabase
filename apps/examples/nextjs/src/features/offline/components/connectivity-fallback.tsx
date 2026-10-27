"use client";

import type { ReactNode } from "react";

import { useExtracted } from "next-intl";
import { useOffline } from "next/offline";

/**
 * The Suspense fallback of an island that reads per request: the island's own
 * skeleton, plus a line that says why it waits while the app is offline.
 */
export function ConnectivityFallback({ children }: { children: ReactNode }) {
  const offline = useOffline();
  const t = useExtracted("offline");

  return (
    <div className="flex flex-col gap-2">
      {children}
      {offline ? (
        <output className="block text-xs text-muted-foreground">
          {t("Waiting for a connection to load this section.")}
        </output>
      ) : null}
    </div>
  );
}
