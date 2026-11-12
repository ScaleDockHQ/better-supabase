"use client";

import { PlusIcon, SearchIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useState } from "react";

import { Button } from "@/components/ui/button";
import {
  InputGroup,
  InputGroupAddon,
  InputGroupInput,
} from "@/components/ui/input-group";
import { ScrollArea } from "@/components/ui/scroll-area";

import type { PaletteEntry, PaletteGroup } from "../editor-model";

/** The media type a palette drag carries, read back by the canvas on drop. */
export const PALETTE_DRAG = "application/x-workflow-palette";

const GROUPS: readonly PaletteGroup[] = [
  "triggers",
  "actions",
  "logic",
  "people",
  "ai",
];

/**
 * Searchable node palette. Each entry comes from the node kind registry or the
 * step library; click adds it below the last node, drag drops it on the
 * canvas.
 */
export function NodePalette({
  entries,
  onAdd,
}: {
  /** The whole palette; the search narrows it here. */
  entries: readonly PaletteEntry[];
  onAdd: (entry: PaletteEntry) => void;
}) {
  const t = useExtracted("workflows");
  const [query, setQuery] = useState("");

  const labels: Readonly<Record<PaletteGroup, string>> = {
    triggers: t("Triggers"),
    actions: t("Actions"),
    logic: t("Logic"),
    people: t("People"),
    ai: t("AI"),
  };

  const needle = query.trim().toLowerCase();

  const shown =
    needle === ""
      ? entries
      : entries.filter((entry) =>
          `${entry.title} ${entry.description} ${entry.id}`
            .toLowerCase()
            .includes(needle),
        );

  return (
    <nav
      className="flex w-56 shrink-0 flex-col gap-2"
      aria-label={t("Palette")}
    >
      <InputGroup>
        <InputGroupAddon>
          <SearchIcon />
        </InputGroupAddon>
        <InputGroupInput
          type="search"
          value={query}
          placeholder={t("Search nodes")}
          aria-label={t("Search nodes")}
          onChange={(event) => {
            setQuery(event.target.value);
          }}
        />
      </InputGroup>
      <ScrollArea className="h-130">
        <div className="flex flex-col gap-3 pr-3">
          {shown.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              {t("No node matches {query}", { query })}
            </p>
          ) : null}
          {GROUPS.map((group) => {
            const items = shown.filter((entry) => entry.group === group);

            return items.length === 0 ? null : (
              <section key={group} className="flex flex-col gap-1">
                <h3 className="text-xs font-medium text-muted-foreground uppercase">
                  {labels[group]}
                </h3>
                {items.map((entry) => (
                  <Button
                    key={entry.id}
                    variant="ghost"
                    size="sm"
                    className="w-full justify-start"
                    title={entry.description}
                    draggable
                    onDragStart={(event) => {
                      event.dataTransfer.setData(PALETTE_DRAG, entry.id);
                      event.dataTransfer.effectAllowed = "move";
                    }}
                    onClick={() => {
                      onAdd(entry);
                    }}
                  >
                    <PlusIcon />
                    <span className="truncate">{entry.title}</span>
                  </Button>
                ))}
              </section>
            );
          })}
        </div>
      </ScrollArea>
    </nav>
  );
}
