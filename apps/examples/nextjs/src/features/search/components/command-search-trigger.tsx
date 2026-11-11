"use client";

import type { ComponentProps } from "react";

import { SearchIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import { Button } from "@/components/ui/button";
import { Kbd } from "@/components/ui/kbd";

/** The header button that opens the command center, closed and open alike. */
export function CommandSearchTrigger(
  props: Omit<ComponentProps<typeof Button>, "children" | "variant" | "size">,
) {
  const t = useExtracted("search");

  return (
    <Button
      variant="ghost"
      size="sm"
      aria-label={t("Search")}
      aria-keyshortcuts="Meta+K Control+K"
      {...props}
    >
      <SearchIcon />
      <span className="hidden sm:inline">{t("Search")}</span>
      <Kbd className="hidden sm:inline-flex">⌘K</Kbd>
    </Button>
  );
}
