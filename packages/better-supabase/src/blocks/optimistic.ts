import type { BlockOptimistic } from "./block-controller.ts";

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null;
}

function isPage(data: unknown): data is { readonly items: readonly unknown[] } {
  return (
    typeof data === "object" &&
    data !== null &&
    "items" in data &&
    Array.isArray(data.items)
  );
}

/** Applies `change` to the rows of a cached list or page; other data stays. */
function overRows(
  data: unknown,
  change: (rows: readonly unknown[]) => readonly unknown[],
): unknown {
  if (Array.isArray(data)) {
    return change(data);
  }

  return isPage(data) ? { ...data, items: change(data.items) } : data;
}

function idOf(row: unknown, key: string): unknown {
  return isRecord(row) ? row[key] : undefined;
}

/** What an optimistic write names: the row it acts on. */
export interface OptimisticRow {
  /** The cached read methods to rewrite, such as `["list", "page"]`. */
  readonly reads: readonly string[];
  /** The row's key in the cached rows. Defaults to `id`. */
  readonly key?: string;
}

/**
 * An `update` that shows the change at once: `target` reads the row's id and
 * the fields to show from the call's arguments.
 */
export function optimisticUpdate<A extends readonly unknown[]>(
  options: OptimisticRow & {
    readonly target: (...args: A) => {
      readonly id: unknown;
      readonly patch: Readonly<Record<string, unknown>>;
    };
  },
): BlockOptimistic<A> {
  const key = options.key ?? "id";

  return {
    reads: options.reads,
    apply: ({ data, args }) => {
      const { id, patch } = options.target(...args);

      return overRows(data, (rows) =>
        rows.map((row) =>
          idOf(row, key) === id && isRecord(row) ? { ...row, ...patch } : row,
        ),
      );
    },
  };
}

/**
 * An `archive` that takes the row out of the cached lists at once (`archived:
 * false` is a restore and leaves them, since the row isn't there to show).
 */
export function optimisticArchive<A extends readonly unknown[]>(
  options: OptimisticRow & {
    readonly target: (...args: A) => {
      readonly id: unknown;
      readonly archived?: boolean | undefined;
    };
  },
): BlockOptimistic<A> {
  const key = options.key ?? "id";

  return {
    reads: options.reads,
    apply: ({ data, args }) => {
      const { id, archived = true } = options.target(...args);

      return archived
        ? overRows(data, (rows) => rows.filter((row) => idOf(row, key) !== id))
        : data;
    },
  };
}

/**
 * A reorder that moves the row in the cached lists at once: `target` gives the
 * row's id and the id it goes before (`undefined` for the end).
 */
export function optimisticReorder<A extends readonly unknown[]>(
  options: OptimisticRow & {
    readonly target: (...args: A) => {
      readonly id: unknown;
      readonly beforeId?: unknown;
    };
  },
): BlockOptimistic<A> {
  const key = options.key ?? "id";

  return {
    reads: options.reads,
    apply: ({ data, args }) => {
      const { id, beforeId } = options.target(...args);

      return overRows(data, (rows) => {
        const moved = rows.find((row) => idOf(row, key) === id);

        if (moved === undefined) {
          return rows;
        }

        const rest = rows.filter((row) => idOf(row, key) !== id);

        const at =
          beforeId === undefined
            ? rest.length
            : rest.findIndex((row) => idOf(row, key) === beforeId);

        return at === -1
          ? rows
          : [...rest.slice(0, at), moved, ...rest.slice(at)];
      });
    },
  };
}
