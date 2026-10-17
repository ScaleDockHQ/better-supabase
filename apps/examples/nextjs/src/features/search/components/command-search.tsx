// #region recipe:command-search
"use client";

import { useCommandSearch } from "better-supabase/blocks/search/react";
import { SearchIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Link } from "@/i18n/navigation";
import { blockConfig } from "@/lib/supabase/blocks.generated";

/** The API schema `gen` wrote for the search block. */
const API_SCHEMA = blockConfig.search.api;

/** Cmd+K over the search index: customers by name, plus recents and favorites. */
export function CommandSearch() {
  const t = useExtracted("search");
  const search = useCommandSearch({ schema: API_SCHEMA });
  const heading = (key: string) => {
    if (key === "favorites") {
      return t("Favorites");
    }
    if (key === "recents") {
      return t("Recent");
    }
    if (key === "customer") {
      return t("Customers");
    }
    return key;
  };
  return (
    <>
      <Button
        variant="ghost"
        size="sm"
        aria-label={t("Search")}
        aria-keyshortcuts="Meta+K Control+K"
        onClick={() => {
          search.setOpen(true);
        }}
      >
        <SearchIcon />
        <span className="hidden sm:inline">{t("Search")}</span>
        <kbd className="hidden text-xs text-muted-foreground sm:inline">⌘K</kbd>
      </Button>
      <Dialog open={search.open} onOpenChange={search.setOpen}>
        <DialogContent className="gap-4 sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>{t("Search")}</DialogTitle>
            <DialogDescription>
              {t("Find a customer by name, even with a typo.")}
            </DialogDescription>
          </DialogHeader>
          <Input
            type="search"
            value={search.query}
            onChange={(event) => {
              search.setQuery(event.target.value);
            }}
            placeholder={t("Search customers")}
            aria-label={t("Search customers")}
          />
          <div className="max-h-80 overflow-y-auto" aria-live="polite">
            {search.error === undefined ? null : (
              <p className="text-sm text-destructive">
                {t("Search failed. Try again.")}
              </p>
            )}
            {search.groups.length === 0 && !search.loading ? (
              <p className="text-sm text-muted-foreground">
                {search.query.trim() === ""
                  ? t("Type to search.")
                  : t("No matches.")}
              </p>
            ) : null}
            {search.groups.map((group) => (
              <section key={group.key} className="mb-3">
                <h3 className="mb-1 text-xs font-medium text-muted-foreground">
                  {heading(group.key)}
                </h3>
                <ul>
                  {group.items.map((item) => (
                    <li key={`${item.subjectType}:${item.subjectId}`}>
                      <Link
                        href={item.url ?? "/"}
                        onClick={() => void search.select(item)}
                        className="block rounded-md px-2 py-1.5 outline-none hover:bg-muted focus-visible:bg-muted"
                      >
                        {item.title ?? item.subjectId}
                      </Link>
                    </li>
                  ))}
                </ul>
              </section>
            ))}
          </div>
        </DialogContent>
      </Dialog>
    </>
  );
}
// #endregion recipe:command-search
