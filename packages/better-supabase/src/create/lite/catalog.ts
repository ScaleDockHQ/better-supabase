export interface RawColumn {
  readonly name: string;
  readonly type: string;
  readonly nullable: boolean;
  readonly default: string | null;
  readonly identity: string | null;
  readonly generated: boolean;
  readonly comment: string | null;
  /** The element type's name for arrays (`uuid`, `text`, `note_kind`). */
  readonly udt: string;
  readonly array: boolean;
  readonly enumValues: readonly string[];
}

export interface RawConstraint {
  readonly name: string;
  readonly type: "p" | "u" | "f";
  readonly columns: readonly string[];
  readonly refSchema: string | null;
  readonly refTable: string | null;
  readonly refColumns: readonly string[] | null;
  readonly onDelete: string | null;
}

export interface RawIndex {
  readonly columns: readonly string[];
  readonly plain: boolean;
}

export interface RawTable {
  readonly schema: string;
  readonly name: string;
  readonly kind: string;
  readonly rls: boolean;
  readonly comment: string | null;
  readonly columns: readonly RawColumn[];
  readonly constraints: readonly RawConstraint[];
  readonly indexes: readonly RawIndex[];
  readonly policies: number;
  readonly triggers: number;
}

export interface RawCatalog {
  readonly tables: readonly RawTable[];
  readonly functions: readonly string[];
}

function schemaList(schemas: readonly string[]): string {
  return schemas.map((name) => `'${name.replaceAll("'", "''")}'`).join(", ");
}

/**
 * One query that returns the whole catalog as JSON, so it runs through the
 * Management API's read-only endpoint in a single call.
 */
export function catalogQuery(schemas: readonly string[] = ["public"]): string {
  const list = schemaList(schemas);

  return `select json_build_object(
  'tables', (
    select coalesce(json_agg(t order by t.schema, t.name), '[]'::json) from (
      select n.nspname as schema, c.relname as name, c.relkind::text as kind,
        c.relrowsecurity as rls,
        obj_description(c.oid, 'pg_class') as comment,
        (select coalesce(json_agg(json_build_object(
            'name', a.attname,
            'type', format_type(a.atttypid, a.atttypmod),
            'nullable', not a.attnotnull,
            'default', pg_get_expr(d.adbin, d.adrelid),
            'identity', nullif(a.attidentity::text, ''),
            'generated', a.attgenerated::text <> '',
            'comment', col_description(c.oid, a.attnum),
            'udt', coalesce(el.typname, ty.typname),
            'array', ty.typcategory = 'A',
            'enumValues', (select coalesce(json_agg(e.enumlabel order by e.enumsortorder), '[]'::json)
              from pg_enum e where e.enumtypid = coalesce(el.oid, ty.oid))
          ) order by a.attnum), '[]'::json)
          from pg_attribute a
          join pg_type ty on ty.oid = a.atttypid
          left join pg_type el on el.oid = ty.typelem and ty.typcategory = 'A'
          left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
          where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped) as columns,
        (select coalesce(json_agg(json_build_object(
            'name', k.conname,
            'type', k.contype::text,
            'columns', (select json_agg(a.attname order by u.ord)
              from unnest(k.conkey) with ordinality as u(attnum, ord)
              join pg_attribute a on a.attrelid = k.conrelid and a.attnum = u.attnum),
            'refSchema', fn.nspname,
            'refTable', fc.relname,
            'refColumns', (select json_agg(a.attname order by u.ord)
              from unnest(k.confkey) with ordinality as u(attnum, ord)
              join pg_attribute a on a.attrelid = k.confrelid and a.attnum = u.attnum),
            'onDelete', k.confdeltype::text
          )), '[]'::json)
          from pg_constraint k
          left join pg_class fc on fc.oid = k.confrelid
          left join pg_namespace fn on fn.oid = fc.relnamespace
          where k.conrelid = c.oid and k.contype in ('p', 'u', 'f')) as constraints,
        (select coalesce(json_agg(json_build_object(
            'columns', (select json_agg(a.attname order by u.ord)
              from unnest(i.indkey::int2[]) with ordinality as u(attnum, ord)
              join pg_attribute a on a.attrelid = i.indrelid and a.attnum = u.attnum),
            'plain', (not i.indisunique and not i.indisprimary
              and i.indpred is null and i.indexprs is null
              and am.amname = 'btree')
          )), '[]'::json)
          from pg_index i
          join pg_class ic on ic.oid = i.indexrelid
          join pg_am am on am.oid = ic.relam
          where i.indrelid = c.oid and not i.indisprimary and not i.indisunique) as indexes,
        (select count(*)::int from pg_policy p where p.polrelid = c.oid) as policies,
        (select count(*)::int from pg_trigger g
          where g.tgrelid = c.oid and not g.tgisinternal) as triggers
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname in (${list}) and c.relkind in ('r', 'p', 'v', 'm')
    ) t
  ),
  'functions', (
    select coalesce(json_agg(n.nspname || '.' || p.proname order by n.nspname, p.proname), '[]'::json)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in (${list}) and p.prokind in ('f', 'p')
  )
) as catalog`;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function str(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

function strings(value: unknown): readonly string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string")
    : [];
}

function records(value: unknown): readonly Record<string, unknown>[] {
  return Array.isArray(value) ? value.filter((item) => isRecord(item)) : [];
}

function readColumn(row: Record<string, unknown>): RawColumn {
  return {
    name: str(row["name"]) ?? "",
    type: str(row["type"]) ?? "",
    nullable: row["nullable"] !== false,
    default: str(row["default"]),
    identity: str(row["identity"]),
    generated: row["generated"] === true,
    comment: str(row["comment"]),
    udt: str(row["udt"]) ?? "",
    array: row["array"] === true,
    enumValues: strings(row["enumValues"]),
  };
}

function readConstraint(row: Record<string, unknown>): RawConstraint {
  const type = str(row["type"]);

  return {
    name: str(row["name"]) ?? "",
    type: type === "p" || type === "u" ? type : "f",
    columns: strings(row["columns"]),
    refSchema: str(row["refSchema"]),
    refTable: str(row["refTable"]),
    refColumns: Array.isArray(row["refColumns"])
      ? strings(row["refColumns"])
      : null,
    onDelete: str(row["onDelete"]),
  };
}

function readTable(row: Record<string, unknown>): RawTable {
  return {
    schema: str(row["schema"]) ?? "public",
    name: str(row["name"]) ?? "",
    kind: str(row["kind"]) ?? "r",
    rls: row["rls"] === true,
    comment: str(row["comment"]),
    columns: records(row["columns"]).map((each) => readColumn(each)),
    constraints: records(row["constraints"]).map((each) =>
      readConstraint(each),
    ),
    indexes: records(row["indexes"]).map((each) => ({
      columns: strings(each["columns"]),
      plain: each["plain"] === true,
    })),
    policies: typeof row["policies"] === "number" ? row["policies"] : 0,
    triggers: typeof row["triggers"] === "number" ? row["triggers"] : 0,
  };
}

/** Reads the one row `catalogQuery` returns; the JSON may arrive as text. */
export function readCatalog(rows: readonly unknown[]): RawCatalog {
  const [row] = rows;
  const cell = isRecord(row) ? row["catalog"] : undefined;

  const catalog: unknown = typeof cell === "string" ? JSON.parse(cell) : cell;

  if (!isRecord(catalog)) {
    throw new TypeError("The catalog query returned an unexpected result.");
  }

  return {
    tables: records(catalog["tables"]).map((each) => readTable(each)),
    functions: strings(catalog["functions"]),
  };
}
