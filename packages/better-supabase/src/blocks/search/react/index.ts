"use client";

import type { CommandSearchActions, CommandSearchSnapshot } from "../client.ts";

import { rpcTransport } from "../../../core/block-transport.ts";
import { useController } from "../../react-controller.ts";
import { useBlockEnv } from "../../react-env.ts";
import { createCommandSearchController } from "../client.ts";
import { createSearch } from "../search.ts";

export {
  groupHits,
  type CommandSearchGroup,
  type CommandSearchItem,
} from "../groups.ts";

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
  /**
   * Toggles the dialog on Cmd+K and Ctrl+K through the client's keyboard
   * port (`webKeyboard()` on the web; none on React Native). Default true.
   */
  readonly shortcut?: boolean;
  /** The schema the calls go to: the module schema (default `better_supabase`), or the API schema from `blocks.<module>.api`. */
  readonly schema?: string;
}

export interface CommandSearchState
  extends CommandSearchSnapshot, CommandSearchActions {}

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
  const { supabase, ports } = useBlockEnv();
  const { schema, organizationId, limit, listLimit, debounceMs } = options;
  const keyboard = (options.shortcut ?? true) ? ports.keyboard : undefined;
  const typesKey = options.types?.join("\u0000") ?? null;
  return useController(
    () =>
      createCommandSearchController({
        client: createSearch({
          transport: rpcTransport(supabase),
          ...(schema === undefined ? {} : { schema }),
        }),
        ...(keyboard === undefined ? {} : { keyboard }),
        organizationId: organizationId ?? null,
        ...(typesKey === null ? {} : { types: typesKey.split("\u0000") }),
        ...(limit === undefined ? {} : { limit }),
        ...(listLimit === undefined ? {} : { listLimit }),
        ...(debounceMs === undefined ? {} : { debounceMs }),
      }),
    [
      supabase,
      schema,
      keyboard,
      organizationId,
      typesKey,
      limit,
      listLimit,
      debounceMs,
    ],
  ).view;
}
