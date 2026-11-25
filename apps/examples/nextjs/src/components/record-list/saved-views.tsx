"use client";

import type { Route } from "next";

import { BookmarkIcon, Trash2Icon } from "lucide-react";
import { useExtracted } from "next-intl";
import { usePathname, useRouter } from "next/navigation";
import { useState, useSyncExternalStore } from "react";
import * as v from "valibot";

import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Input } from "@/components/ui/input";

export interface SavedView {
  readonly name: string;
  /** The query string of the list, without the leading `?`. */
  readonly search: string;
}

const VERSION = "v1";
const EVENT = "bsb-saved-views";

const storageKey = (scope: string): string => `savedViews:${VERSION}:${scope}`;

function getViews(scope: string): string {
  try {
    return localStorage.getItem(storageKey(scope)) ?? "[]";
  } catch {
    return "[]";
  }
}

const ViewsSchema = v.array(v.object({ name: v.string(), search: v.string() }));

/** The views stored for `scope`; a damaged entry reads as none. */
export function parseViews(raw: string): readonly SavedView[] {
  try {
    const parsed = v.safeParse(ViewsSchema, JSON.parse(raw));

    return parsed.success ? parsed.output : [];
  } catch {
    return [];
  }
}

function write(scope: string, views: readonly SavedView[]): void {
  try {
    localStorage.setItem(storageKey(scope), JSON.stringify(views));

    window.dispatchEvent(new Event(EVENT));
  } catch {
    // Private browsing or a full quota: the view is not kept.
  }
}

function subscribe(onChange: () => void): () => void {
  window.addEventListener(EVENT, onChange);
  window.addEventListener("storage", onChange);

  return () => {
    window.removeEventListener(EVENT, onChange);
    window.removeEventListener("storage", onChange);
  };
}

/**
 * Saved views of a list: named query strings kept in this browser under `scope`
 * (one per list). Applying one replaces the URL, which is the list's whole
 * state. The server snapshot is empty, so the first paint matches.
 */
export function SavedViews({
  scope,
  search,
}: {
  scope: string;
  /** The current query string of the list. */
  search: string;
}) {
  const t = useExtracted("recordList");
  const router = useRouter();
  const pathname = usePathname();
  const [name, setName] = useState("");

  const raw = useSyncExternalStore(
    subscribe,
    () => getViews(scope),
    () => "[]",
  );

  const views = parseViews(raw);

  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        render={
          <Button size="sm" variant="outline">
            <BookmarkIcon />
            {t("Views")}
          </Button>
        }
      />
      <DropdownMenuContent align="start" className="w-64">
        <DropdownMenuLabel>{t("Saved views")}</DropdownMenuLabel>
        {views.length === 0 ? (
          <DropdownMenuLabel className="font-normal text-muted-foreground">
            {t("Nothing saved yet.")}
          </DropdownMenuLabel>
        ) : (
          views.map((view) => (
            <DropdownMenuItem
              key={view.name}
              onClick={() => {
                // SAFETY: `pathname` is the current route; the query is the list's own.
                router.replace(
                  (view.search === ""
                    ? pathname
                    : `${pathname}?${view.search}`) as Route,
                );
              }}
            >
              <span className="flex-1 truncate">{view.name}</span>
              <Button
                size="icon-xs"
                variant="ghost"
                aria-label={t("Delete view {name}", { name: view.name })}
                onClick={(event) => {
                  event.stopPropagation();
                  write(
                    scope,
                    views.filter((item) => item.name !== view.name),
                  );
                }}
              >
                <Trash2Icon />
              </Button>
            </DropdownMenuItem>
          ))
        )}
        <DropdownMenuSeparator />
        <form
          className="flex gap-2 p-1"
          onSubmit={(event) => {
            event.preventDefault();

            const trimmed = name.trim();

            if (trimmed !== "") {
              write(scope, [
                ...views.filter((item) => item.name !== trimmed),
                { name: trimmed, search },
              ]);
              setName("");
            }
          }}
        >
          <Input
            value={name}
            placeholder={t("Name this view")}
            aria-label={t("Name this view")}
            onChange={(event) => {
              setName(event.target.value);
            }}
            onKeyDown={(event) => {
              event.stopPropagation();
            }}
          />
          <Button type="submit" size="sm" disabled={name.trim() === ""}>
            {t("Save")}
          </Button>
        </form>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
