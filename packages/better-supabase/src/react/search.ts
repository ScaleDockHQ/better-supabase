"use client";

import { useEffect, useState } from "react";

import { escapeLike } from "../ir/escape-like.ts";

export interface DebouncedSearchOptions {
  /** Defaults to 250 ms. */
  readonly delayMs?: number;
  /** Shorter terms count as no search. Defaults to 1. */
  readonly minLength?: number;
}

export interface DebouncedSearch {
  /** What the input shows; updates on every keystroke. */
  readonly value: string;
  readonly setValue: (value: string) => void;
  /** The trimmed value once typing pauses, or `undefined` below `minLength`. */
  readonly term: string | undefined;
  /** `term` with `%` and `_` escaped and wrapped in `%`, for `like` and `ilike`. */
  readonly pattern: string | undefined;
  /** `value` changed and `term` hasn't caught up yet. */
  readonly pending: boolean;
}

/**
 * A search box's value, debounced. Pass `term` to `contains` (which
 * escapes it) or `pattern` to `ilike`; both are `undefined` while empty.
 *
 * ```tsx
 * const search = useDebouncedSearch();
 * useQuery(q.customers.findMany({ where: search.term ? { name: { contains: search.term } } : {} }));
 * ```
 */
export function useDebouncedSearch(
  initial = "",
  options: DebouncedSearchOptions = {},
): DebouncedSearch {
  const delayMs = options.delayMs ?? 250;
  const minLength = options.minLength ?? 1;
  const [value, setValue] = useState(initial);
  const [settled, setSettled] = useState(initial);

  useEffect(() => {
    if (value === settled) return;
    const timer = setTimeout(() => {
      setSettled(value);
    }, delayMs);
    return () => {
      clearTimeout(timer);
    };
  }, [value, settled, delayMs]);

  const trimmed = settled.trim();
  const term = trimmed.length >= minLength ? trimmed : undefined;
  return {
    value,
    setValue,
    term,
    pattern: term === undefined ? undefined : `%${escapeLike(term)}%`,
    pending: value !== settled,
  };
}
