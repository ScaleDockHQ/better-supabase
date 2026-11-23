/**
 * The `api` entry of a block: a schema, `false`, or a schema with a function
 * list.
 */
export type BlockApi =
  | string
  | false
  | { readonly schema: string; readonly functions?: readonly string[] }
  | undefined;

/**
 * Whether a block's `api` entry resolves to the project default `sql.api`: the
 * same schema as a string, or as an object that lists no functions. An object
 * with a `functions` list wraps fewer functions than the default, so it never
 * matches here; `restated-probe` renders it to find out whether the list names
 * every function anyway.
 */
export function apiMatches(api: BlockApi, schema: string): boolean {
  if (typeof api === "string") {
    return api === schema;
  }

  return (
    typeof api === "object" &&
    api.schema === schema &&
    api.functions === undefined
  );
}

/** A `sql.api` the blocks would mostly agree on. */
export interface ApiDefaultSuggestion {
  readonly schema: string;
  /** The blocks whose `api` entry repeats the new default and can go. */
  readonly drop: readonly string[];
  /** The blocks with no `api` entry, which need `api: false` to stay unwrapped. */
  readonly disable: readonly string[];
}

/**
 * The `sql.api` to set when the project has none and most blocks name the same
 * schema without a function list. Blocks with no entry would start to write
 * wrappers under the new default, so each gets `api: false`; a block with
 * another schema, a function list or `false` keeps its entry. It suggests a
 * schema only when it removes more entries than it adds (more than half of the
 * blocks, and at least two).
 */
export function suggestSqlApi(
  apis: Readonly<Record<string, BlockApi>>,
  sqlApi: string | undefined,
): ApiDefaultSuggestion | undefined {
  if (sqlApi !== undefined) {
    return undefined;
  }

  const count = new Map<string, string[]>();

  for (const [name, api] of Object.entries(apis)) {
    const schema =
      typeof api === "string" ? api : api === false ? undefined : api?.schema;

    if (schema !== undefined && apiMatches(api, schema)) {
      count.set(schema, [...(count.get(schema) ?? []), name]);
    }
  }

  const [best] = [...count].toSorted(
    ([a, left], [b, right]) => right.length - left.length || a.localeCompare(b),
  );

  if (best === undefined) {
    return undefined;
  }

  const [schema, drop] = best;
  const total = Object.keys(apis).length;

  if (drop.length < 2 || drop.length * 2 <= total) {
    return undefined;
  }

  return {
    schema,
    drop,
    disable: Object.entries(apis)
      .filter(([, api]) => api === undefined)
      .map(([name]) => name),
  };
}
