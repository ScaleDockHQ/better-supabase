import type { ParserSpec } from "better-supabase/list";

/**
 * The list state of an overview whose rows come from a block's list function
 * (`db.assets.assets`, `db.leases.list`) and not from a table. It has the shape
 * `useRecordListState` and the list kit read from a `defineListQuery`: a search
 * text, a sort, facets and an `after` cursor, parsed from and written to the
 * URL. The route passes the parsed query to the block, which filters in the
 * database.
 */

/** A block's readonly option object while a caller fills it in. */
export type Mutable<T> = { -readonly [K in keyof T]: T[K] };

export interface BlockListQuery<S extends string> {
  readonly q?: string;
  readonly sort: S;
  readonly page: number;
  readonly after?: string;
  /** The selected values per facet key. */
  readonly facets: Readonly<Record<string, readonly string[] | undefined>>;
}

export interface BlockListConfig<S extends string> {
  /** Each facet with the values the URL may hold. */
  readonly facets: readonly {
    readonly key: string;
    readonly values: readonly string[];
  }[];
  readonly sorts: readonly S[];
  readonly defaultSort: S;
}

type ParseResult<Q> =
  | { readonly ok: true; readonly value: Q }
  | { readonly ok: false };

export interface BlockList<S extends string> {
  readonly defaults: BlockListQuery<S>;
  readonly facets: readonly { readonly key: string }[];
  parse(input: URLSearchParams): ParseResult<BlockListQuery<S>>;
  toSearchParams(query: Partial<BlockListQuery<S>>): URLSearchParams;
  nuqs<P>(
    createParser: (spec: ParserSpec<unknown>) => P,
  ): Readonly<Record<string, P>>;
}

const MAX_QUERY_LENGTH = 100;

const sameList = (a: readonly string[], b: readonly string[]): boolean =>
  a.length === b.length && a.every((value, index) => value === b[index]);

const text: ParserSpec<string> = {
  parse: (value) => (value === "" ? null : value.slice(0, MAX_QUERY_LENGTH)),
  serialize: String,
};

const cursor: ParserSpec<string> = {
  parse: (value) => (value === "" ? null : value),
  serialize: String,
};

const pageNumber: ParserSpec<number> = {
  parse: (value) => {
    const page = Number(value);

    return Number.isInteger(page) && page > 0 ? page : null;
  },
  serialize: String,
};

/**
 * A list over a block's list function. The values of each facet are checked
 * against its picklist, so a hand-edited URL never reaches the block.
 */
export function defineBlockList<S extends string>(
  config: BlockListConfig<S>,
): BlockList<S> {
  const sortParser: ParserSpec<S> = {
    parse: (value) => config.sorts.find((sort) => sort === value) ?? null,
    serialize: String,
  };

  const facetParser = (
    values: readonly string[],
  ): ParserSpec<readonly string[]> => ({
    parse: (value) => {
      const picked = value.split(",").filter((item) => values.includes(item));

      return picked.length > 0 ? picked : null;
    },
    serialize: (value) => value.join(","),
    eq: sameList,
  });

  const nuqs = <P>(
    createParser: (spec: ParserSpec<unknown>) => P,
  ): Readonly<Record<string, P>> => {
    const entries: [string, P][] = [
      ["q", createParser(text)],
      ["sort", createParser(sortParser)],
      ["page", createParser(pageNumber)],
      ["after", createParser(cursor)],
    ];

    for (const facet of config.facets) {
      entries.push([facet.key, createParser(facetParser(facet.values))]);
    }

    return Object.fromEntries(entries);
  };

  return {
    defaults: { sort: config.defaultSort, page: 1, facets: {} },
    facets: config.facets.map(({ key }) => ({ key })),
    parse(input) {
      const facets: Record<string, readonly string[]> = {};

      for (const facet of config.facets) {
        const raw = input.get(facet.key);

        const picked =
          raw === null ? null : facetParser(facet.values).parse(raw);

        if (picked !== null) {
          facets[facet.key] = picked;
        }
      }

      const q = text.parse(input.get("q") ?? "");
      const after = cursor.parse(input.get("after") ?? "");

      const value: Mutable<BlockListQuery<S>> = {
        sort: sortParser.parse(input.get("sort") ?? "") ?? config.defaultSort,
        page: pageNumber.parse(input.get("page") ?? "") ?? 1,
        facets,
      };

      if (q !== null) {
        value.q = q;
      }

      if (after !== null) {
        value.after = after;
      }

      return { ok: true, value };
    },
    toSearchParams(query) {
      const params = new URLSearchParams();

      if (query.q) {
        params.set("q", query.q);
      }

      if (query.sort && query.sort !== config.defaultSort) {
        params.set("sort", query.sort);
      }

      if (query.after) {
        params.set("after", query.after);
      }

      for (const facet of config.facets) {
        const values = query.facets?.[facet.key];

        if (values && values.length > 0) {
          params.set(facet.key, values.join(","));
        }
      }

      return params;
    },
    nuqs,
  };
}
