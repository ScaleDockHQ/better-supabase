import type { BlockSqlContext } from "../context.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { fail, lockTable, SERVICE_CALLER } from "../shared.ts";

type Column = (logical: string) => string;

export interface OfflineSqlInput {
  readonly t: string;
  readonly c: Column;
  readonly versions: string;
  readonly vc: Column;
  readonly current: (row: string) => string;
  readonly atCurrent: (row: string, path: string) => string;
  readonly buckets: readonly string[];
  readonly requireScan: boolean;
  /** `ctx.record` of `attachment.uploaded`, reading `v_row`. */
  readonly uploaded: string;
}

export interface OfflineSql {
  /** The storage delete policy's check, on `bucket_id` and `name`. */
  readonly deleteCheck: string;
  readonly sql: string;
}

/**
 * `options.offline`: an upload marks its record uploaded from a trigger on
 * `storage.objects`, and a deleted record queues its objects in
 * `attachment_cleanup`, which the caller's own delete or `sweepQueued`
 * empties.
 */
export function attachmentsOfflineSql(
  ctx: BlockSqlContext,
  input: OfflineSqlInput,
): OfflineSql {
  const { t, c, versions, vc, current, atCurrent } = input;
  const fn = (name: string): string => ctx.fn(name);
  const cleanup = ctx.table("cleanup");
  const k = (logical: string): string => ctx.col("cleanup", logical);

  const trigger = (what: string): string =>
    sqlIdent(`bsb_${ctx.tableName("attachments").name}_${what}`);

  const bucketList = input.buckets.map(sqlString).join(", ");

  return {
    deleteCheck: `${fn("attachment_object_queued")}(bucket_id, name)`,
    sql: `
-- options.offline: an object written to an attachment's current path marks
-- the record uploaded, so a client without the network for confirm() still
-- gets its file through. confirm_attachment returns early afterwards.
create or replace function ${fn("attachment_object_uploaded")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t};
begin
  update ${t} a set
    ${c("uploadedAt")} = now(),
    ${c("size")} = coalesce((new.metadata ->> 'size')::bigint, a.${c("size")}),
    ${c("mimeType")} = coalesce(lower(new.metadata ->> 'mimetype'), a.${c("mimeType")})${input.requireScan ? "" : `,\n    ${c("status")} = 'clean'`}
  where a.${c("bucket")} = new.bucket_id and ${atCurrent("a", "new.name")}
    and a.${c("uploadedAt")} is null
  returning * into v_row;
  if v_row.${c("id")} is not null then
    ${input.uploaded}
  end if;
  return null;
end;
$$;
revoke execute on function ${fn("attachment_object_uploaded")}() from public, anon, authenticated;
drop trigger if exists ${trigger("object_uploaded")} on storage.objects;
create trigger ${trigger("object_uploaded")}
  after insert on storage.objects
  for each row when (new.bucket_id in (${bucketList}))
  execute function ${fn("attachment_object_uploaded")}();

-- The objects of deleted records, until the caller deletes them or
-- sweepQueued() does with the service role.
create table if not exists ${cleanup} (
  ${k("bucket")} text not null,
  ${k("path")} text not null,
  ${k("queuedBy")} uuid,
  ${k("queuedAt")} timestamptz not null default now(),
  ${k("attempts")} integer not null default 0,
  primary key (${k("bucket")}, ${k("path")})
);${ctx.owns("cleanup") ? "" : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName("cleanup").name}_object_key`)} on ${cleanup} (${k("bucket")}, ${k("path")});`}
${lockTable(cleanup)}

-- Before delete, since the versions cascade away with the record.
create or replace function ${fn("attachment_queue_cleanup")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into ${cleanup} (${k("bucket")}, ${k("path")}, ${k("queuedBy")})
  select old.${c("bucket")}, ${current("old")}, auth.uid()
  union
  select v.${vc("bucket")}, v.${vc("path")}, auth.uid() from ${versions} v
  where v.${vc("attachment")} = old.${c("id")}
  on conflict (${k("bucket")}, ${k("path")}) do update
    set ${k("queuedBy")} = excluded.${k("queuedBy")}, ${k("queuedAt")} = now();
  return old;
end;
$$;
revoke execute on function ${fn("attachment_queue_cleanup")}() from public, anon, authenticated;
drop trigger if exists ${trigger("queue_cleanup")} on ${t};
create trigger ${trigger("queue_cleanup")}
  before delete on ${t}
  for each row execute function ${fn("attachment_queue_cleanup")}();

create or replace function ${fn("attachment_object_removed")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from ${cleanup} q where q.${k("bucket")} = old.bucket_id and q.${k("path")} = old.name;
  return null;
end;
$$;
revoke execute on function ${fn("attachment_object_removed")}() from public, anon, authenticated;
drop trigger if exists ${trigger("object_removed")} on storage.objects;
create trigger ${trigger("object_removed")}
  after delete on storage.objects
  for each row when (old.bucket_id in (${bucketList}))
  execute function ${fn("attachment_object_removed")}();

-- The storage delete policy: the caller queued the object by deleting its
-- record, and no record or version uses the path again.
create or replace function ${fn("attachment_object_queued")}(bucket text, path text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from ${cleanup} q
    where q.${k("bucket")} = attachment_object_queued.bucket and q.${k("path")} = attachment_object_queued.path
      and q.${k("queuedBy")} = auth.uid()
  ) and not exists (
    select 1 from ${t} a
    where a.${c("bucket")} = attachment_object_queued.bucket and ${atCurrent("a", "attachment_object_queued.path")}
  ) and not exists (
    select 1 from ${versions} v
    where v.${vc("bucket")} = attachment_object_queued.bucket and v.${vc("path")} = attachment_object_queued.path
  )
$$;
revoke execute on function ${fn("attachment_object_queued")}(text, text) from public, anon;
grant execute on function ${fn("attachment_object_queued")}(text, text) to authenticated, service_role;

-- The oldest queued objects, for sweepQueued() (service role). A path a
-- record took again leaves the queue instead.
create or replace function ${fn("queued_attachment_objects")}(max_items integer default 100)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_items jsonb;
begin
  if not (${SERVICE_CALLER}) then
    ${fail("ATTACHMENT_FORBIDDEN", "Only the service role sweeps queued objects")}
  end if;
  delete from ${cleanup} q
  where exists (
    select 1 from ${t} a where a.${c("bucket")} = q.${k("bucket")} and ${atCurrent("a", `q.${k("path")}`)}
  ) or exists (
    select 1 from ${versions} v where v.${vc("bucket")} = q.${k("bucket")} and v.${vc("path")} = q.${k("path")}
  );
  with picked as (
    select q.${k("bucket")} as bucket, q.${k("path")} as path from ${cleanup} q
    order by q.${k("queuedAt")}, q.${k("bucket")}, q.${k("path")}
    limit greatest(least(queued_attachment_objects.max_items, 1000), 1)
    for update skip locked
  ), bumped as (
    update ${cleanup} q set ${k("attempts")} = q.${k("attempts")} + 1
    from picked p where q.${k("bucket")} = p.bucket and q.${k("path")} = p.path
    returning q.${k("bucket")} as bucket, q.${k("path")} as path, q.${k("attempts")} as attempts, q.${k("queuedAt")} as queued_at
  )
  select coalesce(jsonb_agg(jsonb_build_object('bucket', b.bucket, 'path', b.path, 'attempts', b.attempts)
    order by b.queued_at, b.bucket, b.path), '[]'::jsonb)
  into v_items from bumped b;
  return v_items;
end;
$$;

-- Drops swept objects from the queue (service role); returns how many.
create or replace function ${fn("complete_attachment_cleanup")}(objects jsonb)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (${SERVICE_CALLER}) then
    ${fail("ATTACHMENT_FORBIDDEN", "Only the service role sweeps queued objects")}
  end if;
  delete from ${cleanup} q
  using jsonb_array_elements(coalesce(complete_attachment_cleanup.objects, '[]'::jsonb)) as o (item)
  where q.${k("bucket")} = o.item ->> 'bucket' and q.${k("path")} = o.item ->> 'path';
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function ${fn("queued_attachment_objects")}(integer) from public, anon, authenticated;
revoke execute on function ${fn("complete_attachment_cleanup")}(jsonb) from public, anon, authenticated;
grant execute on function ${fn("queued_attachment_objects")}(integer) to service_role;
grant execute on function ${fn("complete_attachment_cleanup")}(jsonb) to service_role;`,
  };
}

/** Drops what `attachmentsOfflineSql` creates, when `options.offline` is off. */
export function attachmentsOnlineSql(ctx: BlockSqlContext, t: string): string {
  const trigger = (what: string): string =>
    sqlIdent(`bsb_${ctx.tableName("attachments").name}_${what}`);

  return `
drop trigger if exists ${trigger("object_uploaded")} on storage.objects;
drop trigger if exists ${trigger("object_removed")} on storage.objects;
drop trigger if exists ${trigger("queue_cleanup")} on ${t};`;
}
