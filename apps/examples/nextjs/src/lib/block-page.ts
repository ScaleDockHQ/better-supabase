import type { PageOptions } from "better-supabase/blocks";

import type { Mutable } from "@/lib/block-status-list";

/** One page of a block list, with the cursor of the next one. */
export interface BlockPage<Row> {
  readonly items: readonly Row[];
  readonly nextCursor: string | null;
}

/**
 * The URL form of a keyset cursor (`nextCursor` of a block page), so the list's
 * `after` parameter carries it unchanged.
 */
export function encodeCursor(cursor: readonly string[] | null): string | null {
  return cursor === null ? null : JSON.stringify(cursor);
}

/** The keyset cursor an `after` parameter holds; none for a malformed one. */
function decodeCursor(
  after: string | undefined,
): readonly string[] | undefined {
  if (after === undefined) {
    return undefined;
  }

  try {
    const parsed: unknown = JSON.parse(after);

    return Array.isArray(parsed) &&
      parsed.every((part): part is string => typeof part === "string")
      ? parsed
      : undefined;
  } catch {
    return undefined;
  }
}

/**
 * The block page options of a list query: its search text, the keyset cursor
 * `after` holds, `limit` rows, and the selected values of each facet as list
 * filters (a facet with no value leaves its filter off).
 */
export function pageOptionsOf(
  query: {
    readonly q?: string | undefined;
    readonly after?: string | undefined;
  },
  limit: number,
  filters: Readonly<Record<string, readonly string[]>> = {},
): PageOptions {
  const options: Mutable<PageOptions> = { limit };

  if (query.q !== undefined) {
    options.q = query.q;
  }

  const after = decodeCursor(query.after);

  if (after !== undefined) {
    options.after = after;
  }

  const set = Object.fromEntries(
    Object.entries(filters).filter(([, values]) => values.length > 0),
  );

  if (Object.keys(set).length > 0) {
    options.filters = set;
  }

  return options;
}
