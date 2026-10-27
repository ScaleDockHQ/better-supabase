"use client";

import type { ReactNode } from "react";

import { useExtracted } from "next-intl";
import { useOffline } from "next/offline";

/**
 * A submit button's label. A Server Action sent while offline stays pending
 * until the connection returns, so the label says what the button waits for.
 */
export function SubmitLabel({
  pending,
  children,
}: {
  pending: boolean;
  children: ReactNode;
}) {
  const offline = useOffline();
  const t = useExtracted("offline");

  return pending && offline ? t("Waiting for connection") : children;
}
