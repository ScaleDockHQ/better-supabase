/** The channel the job modules' statement triggers notify on. */
export const WORK_CHANNEL = "better_supabase_work";

export type WorkKind = "inbox" | "outbox" | "queue";

/**
 * A statement trigger function that sends one `pg_notify` per insert statement
 * that added rows. A notification is delivered on commit, so a rolled-back
 * write wakes nobody. `queue` names where the queue comes from: a column of the
 * inserted rows (one notification per queue) or the trigger's first argument.
 */
export function workNotifyFunction(
  fn: string,
  kind: WorkKind,
  queue?: { readonly column: string } | "argument",
): string {
  const notify = (payload: string): string =>
    `pg_catalog.pg_notify('${WORK_CHANNEL}', ${payload})`;

  let body: string;

  if (queue === undefined) {
    body = `if exists (select 1 from new_rows) then
    perform ${notify(`'{"kind":"${kind}"}'`)};
  end if;`;
  } else if (queue === "argument") {
    body = `if exists (select 1 from new_rows) then
    perform ${notify(`pg_catalog.json_build_object('kind', '${kind}', 'queue', tg_argv[0])::text`)};
  end if;`;
  } else {
    body = `perform ${notify(`pg_catalog.json_build_object('kind', '${kind}', 'queue', q.queue)::text`)}
  from (select distinct n.${queue.column} as queue from new_rows n) q;`;
  }

  return `-- Wakes listenForWork (better-supabase/postgres) on channel ${WORK_CHANNEL}.
create or replace function ${fn}()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  ${body}
  return null;
end;
$$;
revoke all on function ${fn}() from public;`;
}

/** The statement trigger on `table` that calls `fn` with `args`. */
export function workNotifyTrigger(
  table: string,
  fn: string,
  args = "",
): string {
  return `create or replace trigger bsb_notify_work
  after insert on ${table}
  referencing new table as new_rows
  for each statement execute function ${fn}(${args});`;
}
