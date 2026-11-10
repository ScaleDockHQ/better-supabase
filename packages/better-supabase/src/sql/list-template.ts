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

  return `v_limit integer := ${pageSize(`(${filters} ->> 'limit')::integer`, options.defaultLimit ?? 50, options.maxLimit ?? 200)};
  v_offset integer := greatest(coalesce((${filters} ->> 'offset')::integer, 0), 0);
  v_after jsonb := ${filters} -> 'after';
  v_paged boolean := coalesce((${filters} ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((${filters} ->> 'totalCap')::integer, ${String(LIST_TOTAL_CAP)}), 1), ${String(LIST_TOTAL_CAP * 10)});
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;`;
}

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
  const { alias, keys } = options;
  const filters = options.filters ?? "v_filters";

  const where =
    options.where.length > 0 ? options.where.join("\n        and ") : "true";

  return `if ${filters} ? 'after' and ${filters} ? 'offset' then
    ${options.invalid("after and offset are two ways to page; pass one")}
  end if;
  if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> ${String(keys.length)}) then
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
  ) p;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((${filters} ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from ${options.from} ${alias}
      where ${where}
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;`;
}
