"use client";

import { useExtracted } from "next-intl";
import { useState } from "react";

import type {
  FilterField,
  FilterOption,
  FilterQuery,
} from "@/components/reui/filters/filters";

import { Filters } from "@/components/reui/filters/filters";

import type { RecordListFacet } from "./record-list-types";

type Selected = Readonly<Record<string, readonly string[] | undefined>>;

type Counts = Readonly<Record<string, Readonly<Record<string, number>>>>;

const OPERATORS_ID = "is_any_of";

const toQuery = (
  facets: readonly RecordListFacet[],
  selected: Selected,
): FilterQuery<string[]> => ({
  id: "root",
  type: "group",
  combinator: "and",
  rules: facets.flatMap((facet) => {
    const values = selected[facet.key] ?? [];

    return values.length === 0
      ? []
      : [
          {
            id: facet.key,
            type: "rule" as const,
            path: [facet.key],
            operator: OPERATORS_ID,
            value: [...values],
          },
        ];
  }),
});

const toSelected = (query: FilterQuery<string[]>): Map<string, string[]> => {
  const next = new Map<string, string[]>();

  for (const rule of query.rules) {
    if (rule.type === "rule" && rule.operator === OPERATORS_ID) {
      const [key] = rule.path;

      if (
        key !== undefined &&
        rule.value !== undefined &&
        rule.value.length > 0
      ) {
        next.set(key, rule.value);
      }
    }
  }

  return next;
};

const same = (
  a: readonly string[] | undefined,
  b: readonly string[] | undefined,
): boolean => (a ?? []).join("\u0000") === (b ?? []).join("\u0000");

/**
 * The facet filters of a list as ReUI chips. The chips hold an unfinished rule
 * while a person picks values; only a finished rule reaches the URL, and a URL
 * change from outside (reset, back) replaces the chips.
 */
export function RecordListFacets({
  facets,
  selected,
  counts,
  capped,
  onChange,
}: {
  facets: readonly RecordListFacet[];
  selected: Selected;
  counts: Counts | undefined;
  capped: boolean;
  /** Facet keys to their new values; `null` clears a facet. */
  onChange: (patch: Readonly<Record<string, readonly string[] | null>>) => void;
}) {
  const t = useExtracted("recordList");
  const [query, setQuery] = useState(() => toQuery(facets, selected));
  const [seen, setSeen] = useState(selected);

  if (seen !== selected) {
    setSeen(selected);

    const current = toSelected(query);

    if (
      facets.some((facet) => !same(current.get(facet.key), selected[facet.key]))
    ) {
      setQuery(toQuery(facets, selected));
    }
  }

  const fields: FilterField<string[]>[] = facets.map((facet) => {
    const known = counts?.[facet.key] ?? {};

    const values = new Set([
      ...Object.keys(known),
      ...(selected[facet.key] ?? []),
    ]);

    return {
      id: facet.key,
      label: facet.label,
      type: "multiselect",
      operators: [
        { value: OPERATORS_ID, label: t("is any of"), arity: "many" },
      ],
      options: [...values].map((value): FilterOption => {
        const option: FilterOption = { value, label: facet.valueLabel(value) };
        const count = known[value];

        if (count !== undefined) {
          option.description = capped ? `${count}+` : String(count);
        }

        return option;
      }),
    };
  });

  return (
    <Filters
      fields={fields}
      query={query}
      variant="basic"
      size="sm"
      showClear
      onQueryChange={(next) => {
        setQuery(next);

        const patch = toSelected(next);

        onChange(
          Object.fromEntries(
            facets.map((facet) => [facet.key, patch.get(facet.key) ?? null]),
          ),
        );
      }}
    />
  );
}
