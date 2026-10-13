"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";

import type { DbError } from "../../../core/errors.ts";
import type { SearchHit, SearchUserItem } from "../search.ts";
import type { CommandSearchGroup, CommandSearchItem } from "./groups.ts";

import { rpcTransport } from "../../../core/block-transport.ts";
import { useSupabase } from "../../../react/hooks.ts";
import { createSearch, type Search } from "../search.ts";
import { groupHits } from "./groups.ts";

export {
  groupHits,
  type CommandSearchGroup,
  type CommandSearchItem,
} from "./groups.ts";

export interface UseCommandSearchOptions {
  /** One tenant. Default: every tenant the caller can read. */
  readonly organizationId?: string | null;
  readonly types?: readonly string[];
  /** Results per query. Default 20. */
  readonly limit?: number;
  /** Recents and favorites shown before the user types. Default 5. */
  readonly listLimit?: number;
  /** Milliseconds between the last keystroke and the query. Default 150. */
  readonly debounceMs?: number;
  /** Toggles the dialog on Cmd+K and Ctrl+K. Default true. */
  readonly shortcut?: boolean;
  /** The schema the calls go to: the module schema (default `better_supabase`), or the API schema from `sql.modules.<module>.api`. */
  readonly schema?: string;
}

export interface CommandSearchState {
  readonly open: boolean;
  readonly setOpen: (open: boolean) => void;
  readonly query: string;
  readonly setQuery: (query: string) => void;
  /** Favorites and recents for an empty query, otherwise the matches by subject type. */
  readonly groups: readonly CommandSearchGroup[];
  readonly results: readonly SearchHit[];
  readonly recents: readonly SearchUserItem[];
  readonly favorites: readonly SearchUserItem[];
  /** True while a query newer than `results` is running. */
  readonly loading: boolean;
  readonly error: DbError | undefined;
  /** Records the item as opened (for recents) and closes the dialog. */
  readonly select: (item: CommandSearchItem) => Promise<void>;
  readonly star: (item: CommandSearchItem, starred?: boolean) => Promise<void>;
}

const EMPTY: readonly never[] = [];

interface UserLists {
  readonly recents?: readonly SearchUserItem[];
  readonly favorites?: readonly SearchUserItem[];
  readonly error?: DbError;
}

async function loadUserLists(
  client: Search,
  limit: number,
  types: readonly string[] | undefined,
): Promise<UserLists> {
  const list = { limit, ...(types ? { types } : {}) };
  const [recent, starred] = await Promise.all([
    client.recents(list),
    client.favorites(list),
  ]);
  const error = recent.ok
    ? starred.ok
      ? undefined
      : starred.error
    : recent.error;
  return {
    ...(recent.ok ? { recents: recent.data } : {}),
    ...(starred.ok ? { favorites: starred.data } : {}),
    ...(error === undefined ? {} : { error }),
  };
}

/**
 * State for a Cmd+K dialog over the `search` module: a debounced query that
 * ignores stale responses, favorites and recents for an empty query, and
 * `select` that records the open. Render it with any command palette.
 *
 * ```tsx
 * const search = useCommandSearch({ organizationId });
 * <CommandDialog open={search.open} onOpenChange={search.setOpen}>
 *   <CommandInput value={search.query} onValueChange={search.setQuery} />
 * </CommandDialog>
 * ```
 */
export function useCommandSearch(
  options: UseCommandSearchOptions = {},
): CommandSearchState {
  const supabase = useSupabase();
  const schema = options.schema;
  const client = useMemo(
    () =>
      createSearch({
        transport: rpcTransport(supabase),
        ...(schema === undefined ? {} : { schema }),
      }),
    [supabase, schema],
  );
  const organizationId = options.organizationId ?? null;
  const limit = options.limit ?? 20;
  const listLimit = options.listLimit ?? 5;
  const debounceMs = options.debounceMs ?? 150;
  const shortcut = options.shortcut ?? true;
  const typesKey = options.types?.join("\u0000") ?? null;
  const types = useMemo(
    () => (typesKey === null ? undefined : typesKey.split("\u0000")),
    [typesKey],
  );

  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [answer, setAnswer] = useState<{
    q: string;
    hits: readonly SearchHit[];
  }>({ q: "", hits: EMPTY });
  const [recents, setRecents] = useState<readonly SearchUserItem[]>(EMPTY);
  const [favorites, setFavorites] = useState<readonly SearchUserItem[]>(EMPTY);
  const [error, setError] = useState<DbError | undefined>(undefined);
  const latest = useRef(0);

  useEffect(() => {
    if (!shortcut) return;
    const onKey = (event: KeyboardEvent) => {
      if (
        event.key.toLowerCase() === "k" &&
        (event.metaKey || event.ctrlKey) &&
        !event.altKey &&
        !event.shiftKey
      ) {
        event.preventDefault();
        setOpen((current) => !current);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => {
      window.removeEventListener("keydown", onKey);
    };
  }, [shortcut]);

  const applyLists = useCallback((lists: UserLists) => {
    if (lists.recents) setRecents(lists.recents);
    if (lists.favorites) setFavorites(lists.favorites);
    if (lists.error) setError(lists.error);
  }, []);

  useEffect(() => {
    if (!open) return;
    let live = true;
    void loadUserLists(client, listLimit, types).then((lists) => {
      if (live) applyLists(lists);
    });
    return () => {
      live = false;
    };
  }, [client, open, listLimit, types, applyLists]);

  const trimmed = query.trim();
  useEffect(() => {
    const request = ++latest.current;
    if (!open || trimmed === "") return;
    const timer = setTimeout(() => {
      void client
        .search(trimmed, {
          limit,
          organizationId,
          ...(types ? { types } : {}),
        })
        .then((result) => {
          if (request !== latest.current) return;
          if (result.ok) {
            setAnswer({ q: trimmed, hits: result.data });
            setError(undefined);
          } else {
            setAnswer((current) => ({ ...current, q: trimmed }));
            setError(result.error);
          }
        });
    }, debounceMs);
    return () => {
      clearTimeout(timer);
    };
  }, [client, open, trimmed, limit, organizationId, types, debounceMs]);
  const results = trimmed === "" ? EMPTY : answer.hits;

  const select = useCallback(
    async (item: CommandSearchItem) => {
      setOpen(false);
      setQuery("");
      const result = await client.touch(item.subjectType, item.subjectId);
      if (!result.ok) setError(result.error);
    },
    [client],
  );

  const star = useCallback(
    async (item: CommandSearchItem, starred = true) => {
      const result = await client.star(
        item.subjectType,
        item.subjectId,
        starred,
      );
      if (!result.ok) {
        setError(result.error);
        return;
      }
      applyLists(await loadUserLists(client, listLimit, types));
    },
    [client, listLimit, types, applyLists],
  );

  const groups = useMemo<readonly CommandSearchGroup[]>(() => {
    if (trimmed !== "") return groupHits(results);
    return [
      { key: "favorites", items: favorites },
      { key: "recents", items: recents },
    ].filter((group) => group.items.length > 0);
  }, [trimmed, results, favorites, recents]);

  return {
    open,
    setOpen,
    query,
    setQuery,
    groups,
    results,
    recents,
    favorites,
    loading: open && trimmed !== "" && answer.q !== trimmed,
    error,
    select,
    star,
  };
}
