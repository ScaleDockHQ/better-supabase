import { parseBsbComment } from "./bsb-tags.ts";
import { columnTagComments } from "./table-facts.ts";

/**
 * The `tables` and `columns` entries that `@bsb` tags in the app's files give
 * (ADR 1190).
 */
export interface MappingTags {
  /** Block to logical table to `schema.table`. */
  readonly tables: Readonly<Record<string, Readonly<Record<string, string>>>>;
  /** Block to logical table to logical column to column name. */
  readonly columns: Readonly<
    Record<string, Readonly<Record<string, Readonly<Record<string, string>>>>>
  >;
}

const TABLE_COMMENT =
  /comment\s+on\s+table\s+(?:"?([a-z_][a-z0-9_]*)"?\.)?"?([a-z_][a-z0-9_]*)"?\s+is\s+'((?:[^']|'')*)'\s*;/giu;

/**
 * The value of a `name=value` tag, which `@bsb block-table=memberships.members`
 * writes as the tag name.
 */
const tagValue = (comment: string, name: string): string | undefined =>
  parseBsbComment(comment)
    .tags.find((tag) => tag.name.startsWith(`${name}=`))
    ?.name.slice(name.length + 1);

/**
 * `@bsb block-table=<block>.<table>` on a table comment maps the logical table
 * to the app's table; `@bsb column=<logical>` on a column of that table maps
 * the logical column. Config entries win over a tag.
 */
export function mappingTagsOf(
  texts: readonly string[],
  schemas: readonly string[],
): MappingTags {
  const tables: Record<string, Record<string, string>> = {};
  const columns: Record<string, Record<string, Record<string, string>>> = {};
  const owner = new Map<string, readonly [string, string]>();

  for (const text of texts) {
    for (const match of text.matchAll(TABLE_COMMENT)) {
      const schema = match[1] ?? "public";

      const value = tagValue(
        (match[3] ?? "").replaceAll("''", "'"),
        "block-table",
      );

      const [block, logical, ...rest] = value?.split(".") ?? [];

      if (
        block === undefined ||
        logical === undefined ||
        rest.length > 0 ||
        !schemas.includes(schema)
      ) {
        continue;
      }

      const table = `${schema}.${match[2] ?? ""}`;

      owner.set(table, [block, logical]);
      (tables[block] ??= {})[logical] = table;
    }
  }

  for (const text of texts) {
    for (const found of columnTagComments(text)) {
      const logical = tagValue(found.comment, "column");
      const mapped = owner.get(`${found.schema}.${found.name}`);

      if (logical !== undefined && mapped !== undefined) {
        const [block, table] = mapped;

        ((columns[block] ??= {})[table] ??= {})[logical] = found.column;
      }
    }
  }

  return { tables, columns };
}

const merged = (
  entry: object | undefined,
  block: string,
  tags: MappingTags,
): object => {
  // SAFETY: the entry is a config block entry; the optional reads below check each field.
  const config = (entry ?? {}) as {
    readonly tables?: Readonly<Record<string, unknown>>;
    readonly columns?: Readonly<
      Record<string, Readonly<Record<string, unknown>>>
    >;
  };

  const columns: Record<string, unknown> = { ...tags.columns[block] };

  for (const [table, own] of Object.entries(config.columns ?? {})) {
    columns[table] = { ...tags.columns[block]?.[table], ...own };
  }

  return {
    ...config,
    tables: { ...tags.tables[block], ...config.tables },
    columns,
  };
};

/**
 * `modules` and `instances` with the tagged mappings under each block's own
 * `tables` and `columns` entries.
 */
export function withMappingTags<
  Modules extends Readonly<Record<string, object | undefined>>,
  Instances extends Readonly<
    Record<string, { readonly block: string; readonly config: object }>
  >,
>(
  modules: Modules,
  instances: Instances,
  tags: MappingTags,
): { readonly modules: Modules; readonly instances: Instances } {
  const tagged = new Set([
    ...Object.keys(tags.tables),
    ...Object.keys(tags.columns),
  ]);

  if (tagged.size === 0) {
    return { modules, instances };
  }

  return {
    // SAFETY: `merged` keeps every key of the entry and adds `tables` and `columns`.
    modules: Object.fromEntries(
      Object.entries(modules).map(([name, entry]) => [
        name,
        tagged.has(name) ? merged(entry, name, tags) : entry,
      ]),
    ) as Modules,
    // SAFETY: as above, for the instance's own config.
    instances: Object.fromEntries(
      Object.entries(instances).map(([name, instance]) => [
        name,
        tagged.has(instance.block) && name === instance.block
          ? { ...instance, config: merged(instance.config, name, tags) }
          : instance,
      ]),
    ) as Instances,
  };
}
