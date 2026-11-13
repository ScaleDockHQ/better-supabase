import { pageSize } from "./shared.ts";

/**
 * One sort key of a list. Keyset paging compares the keys in order, so every
 * key must be `not null` (wrap a nullable expression in `coalesce`) and the
 * last key must be unique, normally the row id.
 */
export interface ListSortKey {
  /** The SQL expression over the row alias, for example `x.created_at`. */
  readonly expr: string;
  readonly dir: "asc" | "desc";
  /** The key's SQL type, used to cast the cursor value back. */
  readonly type: string;
}

export interface ListTemplateOptions {
  /** The function name, for the variable prefix in generated errors. */
  readonly name: string;
  /** The table expression, aliased as `alias`. */
  readonly from: string;
  readonly alias: string;
  /** Predicates over `alias`, joined with `and`; keep one per passed filter. */
  readonly where: readonly string[];
  readonly keys: readonly ListSortKey[];
  /** The JSON of one row, over `alias`. */
  readonly rowJson: string;
  /** The jsonb variable that holds the caller's filters. Default `v_filters`. */
  readonly filters?: string;
  readonly defaultLimit?: number;
  readonly maxLimit?: number;
  /** A raise statement for an invalid cursor or filter, given a message. */
  readonly invalid: (message: string) => string;
  /**
   * The named sorts `filters.sort` may pick (ADR 0749), each as its keys. The
   * first key's `dir` is the sort's default direction and `filters.direction`
   * replaces it; `keys` stays the order when no sort is given. The names are
   * the entity's `sorts` in the manifest.
   */
  readonly sorts?: Readonly<Record<string, readonly ListSortKey[]>>;
  /**
   * The facets `filters.facet` may count, each as a SQL expression over `alias`
   * (ADR 0749). The names are the entity's `facets` in the manifest.
   */
  readonly facets?: Readonly<Record<string, string>>;
}

/** The most values one facet returns. */
const FACET_VALUE_LIMIT = 100;

/** The jsonb array of a filter's values: a scalar is a list of one. */
function filterValues(key: string, filters: string): string {
  const value = `${filters} -> '${key}'`;

  return `case when jsonb_typeof(${value}) = 'array' then array(select jsonb_array_elements_text(${value})) else array[${filters} ->> '${key}'] end`;
}

/**
 * Whether a filter holds at least one value: it is not missing, null or an
 * empty list.
 */
export function filterSet(key: string, filters = "v_filters"): string {
  const value = `${filters} -> '${key}'`;

  return `(${value} is not null and jsonb_typeof(${value}) <> 'null' and not (jsonb_typeof(${value}) = 'array' and jsonb_array_length(${value}) = 0))`;
}

/**
 * The predicate for a filter whose value is a list (ADR 0749): the row matches
 * when `expr` holds any of the values. A scalar is a list of one, and a
 * missing, null or empty filter matches every row. `type` is the SQL type of
 * `expr`, so an index on the column stays usable.
 */
export function filterAny(
  key: string,
  expr: string,
  type = "text",
  filters = "v_filters",
): string {
  return `(not ${filterSet(key, filters)} or ${expr} = any((${filterValues(key, filters)})::${type}[]))`;
}

/** The first value of a list filter as text (a scalar is its own first value). */
export function filterFirst(key: string, filters = "v_filters"): string {
  return `nullif(coalesce(${filters} #>> '{${key},0}', ${filters} ->> '${key}'), '')`;
}

/**
 * Whether a flag filter (`mine`, `due`) is set: `true` or a list holding
 * `true`.
 */
export function filterFlag(key: string, filters = "v_filters"): string {
  return `coalesce(${filterFirst(key, filters)} = 'true', false)`;
}

/** The default total cap of an offset list, as `notification_page` (ADR 0598). */
export const LIST_TOTAL_CAP = 10_000;

/**
 * The keyset predicate for rows after the cursor in `cursor` (a jsonb array of
 * the key values as text). Each key may sort either way, so the comparison is
 * written out as `k0 > a0 or (k0 = a0 and k1 > a1)` and so on.
 */
export function keysetPredicate(
  keys: readonly ListSortKey[],
  cursor: string,
): string {
  const cast = (key: ListSortKey, at: number): string =>
    `(${cursor} ->> ${String(at)})::${key.type}`;

  const first = keys[0];

  if (first === undefined) {
    return "true";
  }

  // Keys that all sort one way compare as a row, which an index on the keys
  // seeks into.
  if (keys.every((key) => key.dir === first.dir)) {
    const row = keys.map((key) => key.expr).join(", ");
    const after = keys.map((key, at) => cast(key, at)).join(", ");

    return `(${cursor} is null or (${row}) ${first.dir === "asc" ? ">" : "<"} (${after}))`;
  }

  // Mixed directions can't be a row comparison. The leading bound on the
  // first key still lets an index start at the cursor.
  const branches = keys.map((key, at) => {
    const ties = keys
      .slice(0, at)
      .map((tied, tiedAt) => `${tied.expr} = ${cast(tied, tiedAt)}`);

    const step = `${key.expr} ${key.dir === "asc" ? ">" : "<"} ${cast(key, at)}`;

    return `(${[...ties, step].join(" and ")})`;
  });

  const bound = `${first.expr} ${first.dir === "asc" ? ">=" : "<="} ${cast(first, 0)}`;

  return `(${cursor} is null or (${bound} and (${branches.join(" or ")})))`;
}

/** The `order by` list of `keys`. */
export function listOrder(keys: readonly ListSortKey[]): string {
  return keys.map((key) => `${key.expr} ${key.dir}`).join(", ");
}

/** The cursor of one row: its key values as a jsonb array of text. */
function cursorOf(keys: readonly ListSortKey[]): string {
  return `jsonb_build_array(${keys.map((key) => `(${key.expr})::text`).join(", ")})`;
}

/**
 * The declarations a list function needs (ADR 0637). Put them in the function's
 * `declare` section, next to its own variables.
 */
export function listDeclare(options: ListTemplateOptions): string {
  const filters = options.filters ?? "v_filters";

  const extended = isExtended(options)
    ? `
  v_sort text := nullif(${filters} ->> 'sort', '');
  v_dir text := nullif(${filters} ->> 'direction', '');
  v_facet text := nullif(${filters} ->> 'facet', '');
  v_count boolean := coalesce((${filters} ->> 'count')::boolean, false);
  v_result jsonb;`
    : "";

  return `v_limit integer := ${pageSize(`(${filters} ->> 'limit')::integer`, options.defaultLimit ?? 50, options.maxLimit ?? 200)};
  v_offset integer := greatest(coalesce((${filters} ->> 'offset')::integer, 0), 0);
  v_after jsonb := ${filters} -> 'after';
  v_paged boolean := coalesce((${filters} ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((${filters} ->> 'totalCap')::integer, ${String(LIST_TOTAL_CAP)}), 1), ${String(LIST_TOTAL_CAP * 10)});
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;${extended}`;
}

/** Whether the list takes sorts, facets and a count (ADR 0749). */
function isExtended(options: ListTemplateOptions): boolean {
  return options.sorts !== undefined || options.facets !== undefined;
}

/** `keys` with the first key sorted `dir`. */
function directed(
  keys: readonly ListSortKey[],
  dir: "asc" | "desc",
): readonly ListSortKey[] {
  return keys.map((key, at) => (at === 0 ? { ...key, dir } : key));
}

const quoted = (names: readonly string[]): string =>
  names.map((name) => `'${name}'`).join(", ");

/**
 * The statements that read one page and return it. Without `paged` the result
 * is the plain jsonb array every list returned before. With `{ paged: true }`
 * it is `{ items, hasMore, nextCursor }`, and `{ total: true }` adds `total`
 * and `totalCapped`, counted up to `totalCap` rows. `after` (the previous
 * `nextCursor`) pages by keyset and `offset` pages by number; the two do not
 * combine. Keyset never scans skipped rows, so it is the default; `offset`
 * stays for callers that show page numbers.
 */
export function listBody(options: ListTemplateOptions): string {
  const { alias } = options;
  const filters = options.filters ?? "v_filters";

  const where =
    options.where.length > 0 ? options.where.join("\n        and ") : "true";

  const read = (
    keys: readonly ListSortKey[],
  ): string => `if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> ${String(keys.length)}) then
    ${options.invalid("after is the nextCursor of the previous page")}
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, ${options.rowJson} as j, ${cursorOf(keys)} as k
    from (
      select * from ${options.from} ${alias}
      where ${where}
        and ${keysetPredicate(keys, "v_after")}
      order by ${listOrder(keys)}
      limit v_limit + 1 offset v_offset
    ) ${alias}
  ) p;`;

  const counted = (): string => `select count(*) into v_total from (
      select 1 from ${options.from} ${alias}
      where ${where}
      limit v_total_cap + 1
    ) c;`;

  const reading = isExtended(options)
    ? readExtended(options, read, counted, where)
    : read(options.keys);

  return `if ${filters} ? 'after' and ${filters} ? 'offset' then
    ${options.invalid("after and offset are two ways to page; pass one")}
  end if;
  ${reading}
  if not v_paged then
    return v_items;
  end if;
  if coalesce((${filters} ->> 'total')::boolean, false) then
    ${counted()}
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;`;
}

/**
 * The statements a list with sorts, facets or a count adds before it reads a
 * page (ADR 0749): `filters.facet` returns the counts of one facet,
 * `filters.count` the number of matching rows, and `filters.sort` with
 * `filters.direction` picks the keys the page reads by. Each sort and direction
 * is its own branch, so every order seeks into its own index.
 */
function readExtended(
  options: ListTemplateOptions,
  read: (keys: readonly ListSortKey[]) => string,
  counted: () => string,
  where: string,
): string {
  const { alias } = options;
  const facets = Object.entries(options.facets ?? {});
  const sorts = Object.entries(options.sorts ?? {});

  const facetBranch =
    facets.length === 0
      ? ""
      : `if v_facet is not null then
    if v_facet not in (${quoted(facets.map(([name]) => name))}) then
      ${options.invalid(`facet is one of ${facets.map(([name]) => name).join(", ")}`)}
    end if;
    with s as (
      select (case v_facet ${facets.map(([name, expr]) => `when '${name}' then (${expr})::text`).join(" ")} end) as v
      from ${options.from} ${alias}
      where ${where}
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit ${String(FACET_VALUE_LIMIT)}
    ) g;
    return v_result;
  end if;
  `;

  const countBranch = `if v_count then
    ${counted()}
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  `;

  const checks = `${
    sorts.length === 0
      ? ""
      : `if v_sort is not null and v_sort not in (${quoted(sorts.map(([name]) => name))}) then
    ${options.invalid(`sort is one of ${sorts.map(([name]) => name).join(", ")}`)}
  end if;
  `
  }if v_dir is not null and v_dir not in ('asc', 'desc') then
    ${options.invalid("direction is asc or desc")}
  end if;
  `;

  const variants: { when: string; keys: readonly ListSortKey[] }[] = [];

  const add = (
    name: string | undefined,
    keys: readonly ListSortKey[],
  ): void => {
    const first = keys[0]?.dir ?? "asc";
    const named = name === undefined ? "v_sort is null" : `v_sort = '${name}'`;

    for (const dir of ["asc", "desc"] as const) {
      variants.push({
        when: `${named} and coalesce(v_dir, '${first}') = '${dir}'`,
        keys: dir === first ? keys : directed(keys, dir),
      });
    }
  };

  add(undefined, options.keys);

  for (const [name, keys] of sorts) {
    add(name, keys);
  }

  const branches = variants
    .map(
      (variant, at) =>
        `${at === 0 ? "if" : "elsif"} ${variant.when} then
    ${read(variant.keys)}`,
    )
    .join("\n  ");

  return `${facetBranch}${countBranch}${checks}${branches}
  end if;`;
}
