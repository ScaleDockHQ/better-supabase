"use client";

import { useExtracted } from "next-intl";
import { debounce, useQueryStates } from "nuqs";
import { startTransition } from "react";

import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

import type { AuditFacets } from "../audit-queries";

import { auditSearchParams } from "../audit-search-params";

const ALL = "all";

/**
 * The filter bar. Each change goes to the URL, which re-renders the rows on the
 * server and starts again at the newest page; typing waits 300 ms.
 */
export function AuditFilters({ facets }: { facets: AuditFacets }) {
  const t = useExtracted("audit");

  const [filters, setFilters] = useQueryStates(auditSearchParams, {
    shallow: false,
    startTransition,
  });

  const actorItems = [
    { value: ALL, label: t("Every actor") },
    ...facets.actors.map((actor) => ({ value: actor.id, label: actor.name })),
  ];

  const typeItems = [
    { value: ALL, label: t("Every action") },
    ...facets.types.map((type) => ({ value: type, label: type })),
  ];

  const pick = (value: string | null): string | null =>
    value === null || value === ALL ? null : value;

  return (
    <div className="flex flex-wrap items-center gap-2">
      <Select
        value={filters.actor ?? ALL}
        items={actorItems}
        onValueChange={(value) => {
          void setFilters({ actor: pick(value), before: null });
        }}
      >
        <SelectTrigger size="sm" className="w-48" aria-label={t("Actor")}>
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          {actorItems.map((item) => (
            <SelectItem key={item.value} value={item.value}>
              {item.label}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
      <Select
        value={filters.type ?? ALL}
        items={typeItems}
        onValueChange={(value) => {
          void setFilters({ type: pick(value), before: null });
        }}
      >
        <SelectTrigger size="sm" className="w-56" aria-label={t("Action")}>
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          {typeItems.map((item) => (
            <SelectItem key={item.value} value={item.value}>
              {item.label}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
      <Input
        type="date"
        className="w-40"
        aria-label={t("From")}
        value={filters.from?.slice(0, 10) ?? ""}
        onChange={(event) => {
          const day = event.target.value;

          void setFilters({
            from: day ? `${day}T00:00:00Z` : null,
            before: null,
          });
        }}
      />
      <Input
        type="search"
        className="w-56"
        placeholder={t("Search")}
        aria-label={t("Search")}
        value={filters.q}
        onChange={(event) => {
          void setFilters(
            { q: event.target.value, before: null },
            { limitUrlUpdates: debounce(300) },
          );
        }}
      />
    </div>
  );
}
