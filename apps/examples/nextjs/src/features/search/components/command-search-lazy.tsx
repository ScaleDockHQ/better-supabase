"use client";

import { SearchIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { lazy } from "react";

import { LazyOnIntent } from "@/components/lazy-on-intent";
import { Button } from "@/components/ui/button";

const CommandSearch = lazy(() =>
  import("./command-search").then((mod) => ({ default: mod.CommandSearch })),
);

/**
 * The search button. The dialog and the search hook load on the first hover,
 * focus, click or Cmd+K, and the shortcut opens the dialog once it mounts.
 */
export function CommandSearchLazy() {
  const t = useExtracted("search");

  return (
    <LazyOnIntent
      shortcut
      renderTrigger={(handlers) => (
        <Button
          variant="ghost"
          size="sm"
          aria-label={t("Search")}
          aria-keyshortcuts="Meta+K Control+K"
          {...handlers}
        >
          <SearchIcon />
          <span className="hidden sm:inline">{t("Search")}</span>
          <kbd className="hidden text-xs text-muted-foreground sm:inline">
            ⌘K
          </kbd>
        </Button>
      )}
    >
      <CommandSearch />
    </LazyOnIntent>
  );
}
