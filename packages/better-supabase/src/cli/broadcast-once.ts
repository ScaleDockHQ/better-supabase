/**
 * `realtime.send()` once per transaction and key, for triggers with `dedupe`.
 * The md5 of the topic, event and key is kept in a transaction-local setting,
 * which a commit or rollback clears; nothing is written to a table.
 */
export const BROADCAST_ONCE_SQL: string = `-- better-supabase: realtime.send() once per transaction and key
create schema if not exists better_supabase;
create or replace function better_supabase.broadcast_once(
  payload jsonb,
  event text,
  topic text,
  private boolean,
  key_fields text[]
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  sent text := md5(jsonb_build_array(topic, event, case
    when key_fields is null then payload
    else (select coalesce(jsonb_object_agg(f, payload -> f), '{}') from unnest(key_fields) as f)
  end)::text);
  seen text := coalesce(current_setting('better_supabase.broadcast_sent', true), '');
begin
  if strpos(seen, sent) > 0 then
    return;
  end if;
  perform set_config('better_supabase.broadcast_sent', seen || sent || ' ', true);
  perform realtime.send(payload, event, topic, private);
end;
$$;
revoke execute on function better_supabase.broadcast_once(jsonb, text, text, boolean, text[]) from public, anon, authenticated;
`;

const SEND = /^(\s*)perform realtime\.send\((.*)\);$/gm;

/**
 * A generated broadcast function with each `realtime.send()` turned into
 * `better_supabase.broadcast_once()`. Throws a TypeError for a `dedupeKey`
 * without `dedupe` or with no fields.
 */
export function dedupeTrigger(
  sql: string,
  options: {
    readonly dedupe?: "transaction";
    readonly dedupeKey?: readonly string[];
  },
): string {
  const { dedupe, dedupeKey } = options;

  if (
    dedupeKey !== undefined &&
    (dedupe === undefined || dedupeKey.length === 0)
  ) {
    throw new TypeError("dedupeKey needs dedupe and at least one field");
  }

  if (dedupe === undefined) {
    return sql;
  }

  const key =
    dedupeKey === undefined
      ? "null"
      : `array[${dedupeKey.map((field) => `'${field.replaceAll("'", "''")}'`).join(", ")}]`;

  const deduped = sql.replaceAll(
    SEND,
    (_, indent: string, args: string) =>
      `${indent}perform better_supabase.broadcast_once(${args}, ${key});`,
  );

  if (deduped === sql) {
    throw new TypeError(
      "dedupe needs a generated broadcast function; update better-supabase where the topics import it",
    );
  }

  return deduped;
}
