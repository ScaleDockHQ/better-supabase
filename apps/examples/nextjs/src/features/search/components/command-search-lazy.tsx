"use client";

import { lazy } from "react";

import { LazyOnIntent } from "@/components/lazy-on-intent";

import type { CommandCreate, CommandPage } from "./command-center";

import { CommandSearchTrigger } from "./command-search-trigger";

const NO_PAGES: readonly CommandPage[] = [];
const NO_CREATE: CommandCreate = {};

const CommandCenter = lazy(() =>
  import("./command-center").then((mod) => ({ default: mod.CommandCenter })),
);

/**
 * The search button. The palette and the search hook load on the first hover,
 * focus, click or Cmd+K, and the shortcut opens the palette once it mounts.
 * Without `pages` (the header's fallback while the session loads) the palette
 * still searches records.
 */
export function CommandSearchLazy({
  pages = NO_PAGES,
  canCreate = NO_CREATE,
}: {
  pages?: readonly CommandPage[];
  canCreate?: CommandCreate;
}) {
  return (
    <LazyOnIntent
      shortcut
      renderTrigger={(handlers) => <CommandSearchTrigger {...handlers} />}
    >
      <CommandCenter pages={pages} canCreate={canCreate} />
    </LazyOnIntent>
  );
}
