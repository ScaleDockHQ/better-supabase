"use client";

import { type LiveCountSeed, useLiveCount } from "better-supabase/react";
import { BellIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import { Badge } from "@/components/ui/badge";
import { buttonVariants } from "@/components/ui/button";
import { Link } from "@/i18n/navigation";

import { unreadSpec } from "../inbox-specs";

/**
 * The header badge. Part of the static shell, so it counts from the browser
 * (one HEAD request) instead of adding a database call to every page.
 */
export function UnreadBadge() {
  const t = useExtracted("inbox");
  const { count, status } = useLiveCount(unreadSpec);
  return (
    <Link
      href="/inbox"
      className={buttonVariants({ variant: "ghost", size: "sm" })}
      data-testid="unread-badge"
      data-status={status}
      aria-label={t("Inbox, {count, number} unread", { count: count ?? 0 })}
    >
      <BellIcon />
      <Badge
        variant={count ? "default" : "secondary"}
        className="tabular-nums"
        data-testid="unread-count"
      >
        {count ?? "–"}
      </Badge>
    </Link>
  );
}

/** The inbox summary: renders the server's count, then stays live. */
export function UnreadSummary({ seed }: { seed: LiveCountSeed }) {
  const t = useExtracted("inbox");
  const { count } = useLiveCount(seed);
  return (
    <p className="text-muted-foreground text-sm" data-testid="unread-summary">
      {count === undefined
        ? t("Counting…")
        : t("{count, number} unread", { count })}
    </p>
  );
}
