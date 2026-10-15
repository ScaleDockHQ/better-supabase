import type { KeyboardPort } from "../../client/ports.ts";
import type { DbError } from "../../core/errors.ts";
import type { Controller } from "../controller.ts";
import type { CommandSearchGroup, CommandSearchItem } from "./groups.ts";
import type { Search, SearchHit, SearchUserItem } from "./search.ts";

import { defineController } from "../controller.ts";
import { groupHits } from "./groups.ts";

export interface CommandSearchOptions {
  readonly client: Pick<
    Search,
    "search" | "recents" | "favorites" | "touch" | "star"
  >;
  /** Toggles the dialog on Cmd+K and Ctrl+K. Without it there is no shortcut. */
  readonly keyboard?: KeyboardPort;
  /** One tenant. Default: every tenant the caller can read. */
  readonly organizationId?: string | null;
  readonly types?: readonly string[];
  /** Results per query. Default 20. */
  readonly limit?: number;
  /** Recents and favorites shown before the user types. Default 5. */
  readonly listLimit?: number;
  /** Milliseconds between the last keystroke and the query. Default 150. */
  readonly debounceMs?: number;
}

export interface CommandSearchSnapshot {
  readonly open: boolean;
  readonly query: string;
  /** Favorites and recents for an empty query, otherwise the matches by subject type. */
  readonly groups: readonly CommandSearchGroup[];
  readonly results: readonly SearchHit[];
  readonly recents: readonly SearchUserItem[];
  readonly favorites: readonly SearchUserItem[];
  /** True while a query newer than `results` is running. */
  readonly loading: boolean;
  readonly error: DbError | undefined;
}

export interface CommandSearchActions {
  readonly setOpen: (open: boolean) => void;
  readonly setQuery: (query: string) => void;
  /** Records the item as opened (for recents) and closes the dialog. */
  readonly select: (item: CommandSearchItem) => Promise<void>;
  readonly star: (item: CommandSearchItem, starred?: boolean) => Promise<void>;
}

export type CommandSearchController = Controller<
  CommandSearchSnapshot,
  CommandSearchActions
>;

const EMPTY: readonly never[] = [];

/**
 * State for a Cmd+K dialog over the `search` module: a debounced query that
 * ignores stale responses, favorites and recents for an empty query, and
 * `select` that records the open.
 */
export function createCommandSearchController(
  options: CommandSearchOptions,
): CommandSearchController {
  const { client, types } = options;
  const organizationId = options.organizationId ?? null;
  const limit = options.limit ?? 20;
  const listLimit = options.listLimit ?? 5;
  const debounceMs = options.debounceMs ?? 150;
  const list = { limit: listLimit, ...(types ? { types } : {}) };
  let open = false;
  let query = "";
  let answer: { readonly q: string; readonly hits: readonly SearchHit[] } = {
    q: "",
    hits: EMPTY,
  };
  let recents: readonly SearchUserItem[] = EMPTY;
  let favorites: readonly SearchUserItem[] = EMPTY;
  let error: DbError | undefined;
  let ticket = 0;
  let listTicket = 0;
  let timer: ReturnType<typeof setTimeout> | undefined;

  const view = (): CommandSearchSnapshot => {
    const trimmed = query.trim();
    const results = trimmed === "" ? EMPTY : answer.hits;
    return {
      open,
      query,
      results,
      recents,
      favorites,
      error,
      loading: open && trimmed !== "" && answer.q !== trimmed,
      groups:
        trimmed === ""
          ? [
              { key: "favorites", items: favorites },
              { key: "recents", items: recents },
            ].filter((group) => group.items.length > 0)
          : groupHits(results),
    };
  };

  return defineController<CommandSearchSnapshot, CommandSearchActions>(
    view(),
    (state) => {
      const show = (): void => {
        state.set(view());
      };
      const loadLists = async (): Promise<void> => {
        const request = ++listTicket;
        const [recent, starred] = await Promise.all([
          client.recents(list),
          client.favorites(list),
        ]);
        if (request !== listTicket) return;
        if (recent.ok) recents = recent.data;
        if (starred.ok) favorites = starred.data;
        const failed = recent.ok ? (starred.ok ? undefined : starred) : recent;
        if (failed) error = failed.error;
        show();
      };
      const schedule = (): void => {
        const request = ++ticket;
        clearTimeout(timer);
        timer = undefined;
        const trimmed = query.trim();
        if (!open || trimmed === "") return;
        timer = setTimeout(() => {
          timer = undefined;
          void client
            .search(trimmed, {
              limit,
              organizationId,
              ...(types ? { types } : {}),
            })
            .then((result) => {
              if (request !== ticket) return;
              if (result.ok) {
                answer = { q: trimmed, hits: result.data };
                error = undefined;
              } else {
                answer = { ...answer, q: trimmed };
                error = result.error;
              }
              show();
            });
        }, debounceMs);
      };
      const setOpen = (next: boolean): void => {
        if (next === open) return;
        open = next;
        if (open) {
          void loadLists();
        } else {
          listTicket += 1;
        }
        schedule();
        show();
      };
      return {
        actions: {
          setOpen,
          setQuery: (next) => {
            if (next === query) return;
            const before = query.trim();
            query = next;
            if (query.trim() !== before) schedule();
            show();
          },
          select: async (item) => {
            setOpen(false);
            query = "";
            schedule();
            show();
            const result = await client.touch(item.subjectType, item.subjectId);
            if (!result.ok) {
              error = result.error;
              show();
            }
          },
          star: async (item, starred = true) => {
            const result = await client.star(
              item.subjectType,
              item.subjectId,
              starred,
            );
            if (!result.ok) {
              error = result.error;
              show();
              return;
            }
            await loadLists();
          },
        },
        start: () => {
          const release = options.keyboard?.({ key: "k", mod: true }, () => {
            setOpen(!open);
          });
          return () => {
            release?.();
            clearTimeout(timer);
            timer = undefined;
            ticket += 1;
            listTicket += 1;
          };
        },
      };
    },
  );
}
