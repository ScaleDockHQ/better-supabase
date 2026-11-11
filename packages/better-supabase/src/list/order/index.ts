import type { BetterSupabase } from "../../core/define.ts";
import type { ValidationIssue } from "../../core/errors.ts";
import type {
  AnyFunctions,
  AnyModels,
  Row,
  TableKey,
} from "../../schema/types.ts";
import type { ListFreeSort, ListOrder } from "../list-query.ts";

/** Most terms in a free sort. */
const MAX_ORDER = 3;

function parseOrder(value: string): ListOrder[] | null {
  const order: ListOrder[] = [];

  for (const part of value.split(",")) {
    const term = part.trim();

    if (term === "") {
      continue;
    }

    const [column, direction = "asc", extra] = term.split(":");

    if (
      !column ||
      extra !== undefined ||
      (direction !== "asc" && direction !== "desc")
    ) {
      return null;
    }

    order.push({ column, direction });
  }

  return order.length > 0 ? order : null;
}

const serializeOrder = (order: readonly ListOrder[]): string =>
  order.map((term) => `${term.column}:${term.direction}`).join(",");

function field(term: unknown, key: string): unknown {
  if (typeof term !== "object" || term === null || !(key in term)) {
    return undefined;
  }

  // SAFETY: `key in term` on an object makes the property readable.
  return (term as Record<string, unknown>)[key];
}

export interface FreeSortConfig<M extends AnyModels, T extends keyof M> {
  /** Columns a caller may sort by. */
  readonly sortable: readonly Extract<keyof Row<M, T>, string>[];
  /** The unique column that ends the sort. Defaults to the primary key. */
  readonly tiebreak?: Extract<keyof Row<M, T>, string>;
}

/**
 * A free sort for `defineListQuery`'s `freeSort`: the caller picks up to three
 * of `sortable` and a direction each, as `order=name:asc,createdAt:desc` or as
 * `order: [{ column, direction }]` input (ADR 0672). The tiebreak column ends
 * the sort so cursor pages stay stable.
 */
export function freeSort<
  M extends AnyModels,
  D,
  Fn extends AnyFunctions,
  E,
  T extends TableKey<M>,
>(
  betterSupabase: BetterSupabase<M, D, Fn, E>,
  table: T,
  config: FreeSortConfig<M, T>,
): ListFreeSort {
  const meta = betterSupabase.meta.tables[table];

  if (!meta) {
    throw new TypeError(`freeSort: unknown table "${table}"`);
  }

  const { sortable } = config;
  const tiebreak = config.tiebreak ?? meta.primaryKey[0];

  for (const column of [...sortable, ...(tiebreak ? [tiebreak] : [])]) {
    if (!meta.columns[column]) {
      throw new TypeError(`freeSort: unknown column "${table}.${column}"`);
    }
  }

  if (!tiebreak) {
    throw new TypeError(`freeSort: "${table}" needs a tiebreak column`);
  }

  const refuse = (issues: ValidationIssue[], message: string): void => {
    issues.push({ message, path: ["order"] });
  };

  return {
    sortable,
    check(raw, issues) {
      const terms = typeof raw === "string" ? parseOrder(raw) : raw;

      if (!Array.isArray(terms) || terms.length === 0) {
        refuse(issues, "Must be column:direction pairs, such as name:asc");

        return;
      }

      if (terms.length > MAX_ORDER) {
        refuse(issues, `At most ${String(MAX_ORDER)} sort columns`);

        return;
      }

      const checked: ListOrder[] = [];

      // SAFETY: Array.isArray narrowed the input to an array; each term is checked below.
      for (const term of terms as readonly unknown[]) {
        const column = field(term, "column");
        const direction = field(term, "direction") ?? "asc";

        if (
          typeof column !== "string" ||
          !(sortable as readonly string[]).includes(column) ||
          checked.some((done) => done.column === column) ||
          (direction !== "asc" && direction !== "desc")
        ) {
          refuse(
            issues,
            `Must be a distinct column of: ${sortable.join(", ")}`,
          );

          return;
        }

        checked.push({ column, direction });
      }

      return checked;
    },
    orderBy(order) {
      const terms = order.map((term) => ({ [term.column]: term.direction }));

      return order.some((term) => term.column === tiebreak)
        ? terms
        : [...terms, { [tiebreak]: "asc" }];
    },
    parser: {
      parse: parseOrder,
      serialize: serializeOrder,
      eq: (a, b) => serializeOrder(a) === serializeOrder(b),
    },
    serialize: serializeOrder,
    openapi: {
      name: "order",
      in: "query",
      required: false,
      description: `Free sort, at most ${String(MAX_ORDER)} \`column:direction\` pairs separated by commas. Columns: ${sortable.join(", ")}. Replaces \`sort\`.`,
      schema: { type: "string" },
    },
    jsonSchema: {
      type: "array",
      maxItems: MAX_ORDER,
      items: {
        type: "object",
        additionalProperties: false,
        required: ["column"],
        properties: {
          column: { type: "string", enum: [...sortable] },
          direction: { type: "string", enum: ["asc", "desc"] },
        },
      },
    },
  };
}
