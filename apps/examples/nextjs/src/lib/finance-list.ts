/* oxlint-disable anti-slop/no-unknown-parameters, anti-slop/no-known-value-widening, anti-slop/no-conditional-empty-object-spread -- `exactOptionalPropertyTypes` rejects an explicit `undefined`, so an optional input is spread only when present; 5 findings */
/**
 * Every entity of the finance pages with its list route, the facets its list
 * function filters by and the sorts it knows (`api.finance_list_spec`). The
 * first sort is the default and stays out of the URL. Client-safe: the list
 * state hook and the list route both read it.
 */
export const FINANCE_ENTITIES = {
  invoices: {
    endpoint: "/api/finance/invoices/list",
    facets: ["status", "direction"],
    sorts: ["default", "due", "total"],
  },
  payables: {
    endpoint: "/api/finance/payables/list",
    facets: ["status"],
    sorts: ["default", "due", "total"],
  },
  expenses: {
    endpoint: "/api/finance/expenses/list",
    facets: ["status"],
    sorts: ["default", "total"],
  },
  ledger: {
    endpoint: "/api/finance/ledger/list",
    facets: ["kind"],
    sorts: ["default", "oldest"],
  },
  journal: {
    endpoint: "/api/finance/journal/list",
    facets: ["status", "sourceType"],
    sorts: ["default", "oldest"],
  },
  "billable-time": {
    endpoint: "/api/finance/billable-time/list",
    facets: ["billable", "billed"],
    sorts: ["default", "longest"],
  },
  recurring: {
    endpoint: "/api/finance/recurring/list",
    facets: ["sourceType"],
    sorts: ["default", "amount"],
  },
  tax: {
    endpoint: "/api/finance/tax/list",
    facets: ["status"],
    sorts: ["default", "oldest"],
  },
  periods: {
    endpoint: "/api/finance/periods/list",
    facets: ["status", "kind"],
    sorts: ["default", "oldest"],
  },
  payroll: {
    endpoint: "/api/finance/payroll/list",
    facets: ["status"],
    sorts: ["default", "oldest"],
  },
  "legal-entities": {
    endpoint: "/api/finance/legal-entities/list",
    facets: ["state"],
    sorts: ["default", "newest"],
  },
  funding: {
    endpoint: "/api/finance/funding/list",
    facets: ["status", "period"],
    sorts: ["default", "units"],
  },
  "bank-accounts": {
    endpoint: "/api/finance/bank-accounts/list",
    facets: ["currency"],
    sorts: ["default", "newest"],
  },
  "bank-transactions": {
    endpoint: "/api/finance/bank-transactions/list",
    facets: ["status"],
    sorts: ["default", "amount"],
  },
} as const satisfies Readonly<
  Record<
    string,
    {
      readonly endpoint: string;
      readonly facets: readonly string[];
      readonly sorts: readonly string[];
    }
  >
>;

export type FinanceEntityKey = keyof typeof FINANCE_ENTITIES;

/** The SQL entity a list key reads; payables are the purchase invoices. */
export function financeSqlEntity(entity: FinanceEntityKey): string {
  return entity === "payables" ? "invoices" : entity;
}

/** The facet a list holds at one value whatever the URL says. */
export function financeFixedFacets(
  entity: FinanceEntityKey,
): Readonly<Record<string, readonly string[]>> {
  return entity === "payables" ? { direction: ["purchase"] } : {};
}

export interface FinanceListQuery {
  readonly q?: string;
  readonly sort: string;
  readonly after?: string;
  readonly facets: Readonly<Record<string, readonly string[] | undefined>>;
}

/** What nuqs' `createParser` takes for one URL key. */
interface ParserSpec<T> {
  readonly parse: (value: string) => T | null;
  readonly serialize: (value: T) => string;
  readonly eq?: (a: T, b: T) => boolean;
}

const MAX_Q = 200;
const MAX_VALUES = 20;
const MAX_VALUE = 80;

const text = {
  parse: (value: string) => value,
  serialize: (value: string) => value,
};

const values = {
  parse: (value: string) => {
    const parts = value
      .split(",")
      .map((part) => part.trim())
      .filter((part) => part !== "");

    return parts.length > 0 ? parts : null;
  },
  serialize: (parts: readonly string[]) => parts.join(","),
  eq: (a: readonly string[], b: readonly string[]) =>
    a.join("\u0000") === b.join("\u0000"),
};

const page = {
  parse: (value: string) => (/^\d+$/.test(value) ? Number(value) : null),
  serialize: String,
};

/**
 * A finance list's URL state in the shape `useRecordListState` takes (the same
 * contract as `defineListQuery`): `?q=&sort=&after=&status=a,b`. The route
 * parses the same params, so the page and the list route agree on every state.
 */
export function defineFinanceList(entity: FinanceEntityKey) {
  const config = FINANCE_ENTITIES[entity];

  const sorts: readonly string[] = config.sorts;
  const facetKeys: readonly string[] = config.facets;
  const defaultSort = sorts[0] ?? "default";

  const defaults: FinanceListQuery = { sort: defaultSort, facets: {} };

  return {
    defaults,
    facets: facetKeys.map((key) => ({ key })),
    sorts,
    parse(
      input: URLSearchParams,
    ):
      | { readonly ok: true; readonly value: FinanceListQuery }
      | { readonly ok: false } {
      const q = input.get("q")?.trim().slice(0, MAX_Q);
      const sort = input.get("sort");
      const after = input.get("after");

      const facets: Record<string, readonly string[]> = {};

      for (const key of facetKeys) {
        const raw = input.get(key);
        const parsed = raw === null ? null : values.parse(raw);

        if (parsed) {
          facets[key] = parsed
            .slice(0, MAX_VALUES)
            .map((value) => value.slice(0, MAX_VALUE));
        }
      }

      return {
        ok: true,
        value: {
          ...(q ? { q } : {}),
          sort: sort !== null && sorts.includes(sort) ? sort : defaultSort,
          ...(after ? { after } : {}),
          facets,
        },
      };
    },
    toSearchParams(query: Partial<FinanceListQuery>): URLSearchParams {
      const params = new URLSearchParams();

      if (query.q) {
        params.set("q", query.q);
      }

      if (query.sort && query.sort !== defaultSort) {
        params.set("sort", query.sort);
      }

      if (query.after) {
        params.set("after", query.after);
      }

      for (const key of facetKeys) {
        const selected = query.facets?.[key];

        if (selected && selected.length > 0) {
          params.set(key, values.serialize(selected));
        }
      }

      return params;
    },
    /**
     * Nuqs parsers, one per URL key
     * (`useQueryStates(list.nuqs(createParser))`).
     */
    nuqs<P>(createParser: (spec: ParserSpec<unknown>) => P): Record<string, P> {
      // SAFETY: each spec parses and serializes its own value type, which
      // nuqs receives untyped, as `defineListQuery(...).nuqs` does.
      const untyped = (spec: unknown) =>
        createParser(spec as ParserSpec<unknown>);

      return {
        q: untyped(text),
        sort: untyped(text),
        after: untyped(text),
        page: untyped(page),
        ...Object.fromEntries(facetKeys.map((key) => [key, untyped(values)])),
      };
    },
  };
}

export type FinanceList = ReturnType<typeof defineFinanceList>;
