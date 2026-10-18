import { sqlIdent, sqlString } from "../core/template.ts";

/** One topic a generated broadcast function sends to. */
export interface TriggerTopicSql {
  readonly template: string;
  readonly private: boolean;
  /** Placeholder to its SQL expression on `rec`. */
  readonly values: Readonly<Record<string, string>>;
}

export type TriggerPayloadSql =
  /** `id` is a `jsonb` expression for the primary key. */
  | { readonly kind: "keys"; readonly id: string }
  | { readonly kind: "row" }
  /** A `jsonb` expression. */
  | { readonly kind: "custom"; readonly sql: string };

interface TriggerFunctionSql {
  /** `-- better-supabase: broadcast <subject> changes to <topics>` */
  readonly subject: string;
  readonly functionSchema: string;
  readonly functionName: string;
  readonly triggerName: string;
  /** The quoted `schema.table`. */
  readonly target: string;
  readonly events: string;
  /** The event name, as SQL. */
  readonly event: string;
  readonly topics: readonly TriggerTopicSql[];
  readonly payload: TriggerPayloadSql;
}

/** Marks a generated function that sends whole rows on purpose (doctor reads it). */
const ROW_PAYLOAD_MARKER: string = "better-supabase: payload row";

/** The primary key as `jsonb`, read from the catalog when the table's key isn't known. */
export const CATALOG_ID_SQL: string =
  "(select case when count(*) = 1 then (array_agg(r.j -> a.attname::text))[1] else jsonb_object_agg(a.attname, r.j -> a.attname::text) end" +
  " from pg_catalog.pg_index i" +
  " join pg_catalog.pg_attribute a on a.attrelid = i.indrelid and a.attnum = any(i.indkey::int2[])" +
  " cross join (select to_jsonb(rec) as j) as r" +
  " where i.indrelid = tg_relid and i.indisprimary)";

/** The primary key as `jsonb` from known database columns. */
export function idSql(columns: readonly string[]): string {
  if (columns.length === 0) {
    return "null::jsonb";
  }

  if (columns.length === 1) {
    return `to_jsonb(rec.${sqlIdent(columns[0] ?? "")})`;
  }

  return `jsonb_build_object(${columns
    .map((column) => `${sqlString(column)}, rec.${sqlIdent(column)}`)
    .join(", ")})`;
}

function topicSql(template: string): string {
  return template
    .split(/(\{[^}]+\})/)
    .filter(Boolean)
    .map((part) => {
      const param = /^\{(.+)\}$/.exec(part)?.[1];

      return param === undefined
        ? sqlString(part)
        : `(vals ->> ${sqlString(param)})`;
    })
    .join(" || ");
}

function payloadSql(payload: TriggerPayloadSql): string {
  switch (payload.kind) {
    case "keys": {
      return `jsonb_build_object('operation', tg_op, 'schema', tg_table_schema, 'table', tg_table_name, 'id', ${payload.id}, 'values', vals)`;
    }

    case "row": {
      return "jsonb_build_object('old_record', old, 'record', new, 'operation', tg_op, 'table', tg_table_name, 'schema', tg_table_schema)";
    }

    case "custom": {
      return payload.sql;
    }

    default: {
      const unknown: never = payload;
      throw new TypeError(`unknown payload ${String(unknown)}`);
    }
  }
}

/**
 * A function and row trigger that send one row change to each topic. A
 * topic with a null value is skipped; one with a value topics don't allow
 * is skipped with a warning, so the write still commits.
 */
export function triggerFunctionSql(input: TriggerFunctionSql): string {
  const fn = `${sqlIdent(input.functionSchema)}.${sqlIdent(input.functionName)}`;
  const payload = payloadSql(input.payload);

  const sends = input.topics.flatMap((topic) => {
    const entries = Object.entries(topic.values);

    const vals =
      entries.length === 0
        ? "'{}'::jsonb"
        : `jsonb_build_object(${entries
            .map(([param, value]) => `${sqlString(param)}, (${value})::text`)
            .join(", ")})`;

    return [
      `  -- ${topic.template}`,
      `  vals := ${vals};`,
      "  select e.key, e.value into bad from jsonb_each_text(vals) as e",
      "    where e.value is null or e.value !~ '^[\\w.@+=-]+$'",
      "    order by e.value is null desc limit 1;",
      "  if not found then",
      `    perform realtime.send(${payload}, ${input.event}, ${topicSql(topic.template)}, ${String(topic.private)});`,
      "  elsif bad.value is not null then",
      `    raise warning 'skipped the broadcast on %: topic value % of %.%.% contains characters topics do not allow', ${sqlString(topic.template)}, bad.value, tg_table_schema, tg_table_name, bad.key;`,
      "  end if;",
    ];
  });

  return [
    `-- better-supabase: broadcast ${input.subject} changes to ${input.topics.map((topic) => topic.template).join(", ")}`,
    `create schema if not exists ${sqlIdent(input.functionSchema)};`,
    `create or replace function ${fn}()`,
    "returns trigger",
    "language plpgsql",
    "security definer",
    "set search_path = ''",
    "as $$",
    "declare",
    "  rec record;",
    "  vals jsonb;",
    "  bad record;",
    "begin",
    "  if tg_when <> 'AFTER' then",
    "    raise exception '% runs after the write; as a % trigger it would cancel the write', tg_name, lower(tg_when)",
    "      using errcode = '39P01';",
    "  end if;",
    "  if tg_op = 'DELETE' then rec := old; else rec := new; end if;",
    ...sends,
    "  return null;",
    "end;",
    "$$;",
    `revoke execute on function ${fn}() from public, anon, authenticated;`,
    ...(input.payload.kind === "row"
      ? [`comment on function ${fn}() is ${sqlString(ROW_PAYLOAD_MARKER)};`]
      : []),
    "",
    `drop trigger if exists ${sqlIdent(input.triggerName)} on ${input.target};`,
    `create trigger ${sqlIdent(input.triggerName)} after ${input.events} on ${input.target}`,
    `  for each row execute function ${fn}();`,
    "",
  ].join("\n");
}
