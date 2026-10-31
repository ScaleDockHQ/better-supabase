import type { DriveKit } from "./drive-kit.ts";

import { sqlString } from "../../core/template.ts";
import {
  fail,
  pageSize,
  SERVICE_CALLER,
  serviceGrant,
  userGrant,
} from "../shared.ts";
import { labelTags, usable } from "./drive-kit.ts";

/** The label retention sweep needs labels, the bin and a retention policy store. */
export function driveRetentionSupported(kit: DriveKit): boolean {
  return (
    kit.trash !== undefined &&
    labelTags(kit.own) !== undefined &&
    usable(kit.ctx, "data-lifecycle") !== undefined
  );
}

/**
 * Retention per label: policies of kind `drive_label_<name>` in data-lifecycle
 * (ADR 0034) bin the nodes that carry the label once they were last changed
 * longer ago than the policy keeps them. Legal holds on the kind and drive
 * holds on the node keep it.
 */
export function driveRetentionSql(kit: DriveKit): string {
  const { ctx, own, T, n, fn, live, typeLit, forbidden } = kit;
  const tags = labelTags(own);
  const lifecycle = usable(ctx, "data-lifecycle");

  if (
    !driveRetentionSupported(kit) ||
    tags === undefined ||
    lifecycle === undefined
  ) {
    return "";
  }

  const tg = (column: string): string => tags.col("taggings", column);
  const tt = (column: string): string => tags.col("tags", column);

  const changed = kit.has("updatedAt")
    ? `coalesce(x.${n("updatedAt")}, x.${n("createdAt")})`
    : `x.${n("createdAt")}`;

  const kind = `${fn("drive_retention_kind")}(lt.${tt("name")})`;
  const tenant = `x.${n("tenant")}::text`;

  return `
-- The retention policy kind of a label: drive_label_ and the name in lower
-- case, every run of other characters as one underscore.
create or replace function ${fn("drive_retention_kind")}(label text)
returns text
language sql
immutable
set search_path = ''
as $$
  select 'drive_label_' || left(coalesce(nullif(btrim(regexp_replace(lower(drive_retention_kind.label), '[^a-z0-9]+', '_', 'g'), '_'), ''), 'label'), 50)
$$;
${userGrant(`${fn("drive_retention_kind")}(text)`)}

-- Moves the nodes whose label policy has run out into the bin, oldest first.
-- A node under a hold or a check-out is skipped. Returns how many it binned.
create or replace function ${fn("drive_retention_sweep")}(tenant ${ctx.idType} default null, batch_size integer default 100)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node uuid;
  v_binned integer := 0;
begin
  if not ${SERVICE_CALLER} then
    ${forbidden("sweep retention")}
  end if;
  for v_node in
    select x.${n("id")} from ${T} x
    where (drive_retention_sweep.tenant is null or x.${n("tenant")} = drive_retention_sweep.tenant)${live("x")}
      and exists (
        select 1 from ${tags.table("taggings")} lg
        join ${tags.table("tags")} lt on lt.${tt("id")} = lg.${tg("tag")}
        where lg.${tg("subjectType")} = ${tags.cast("taggings", "subjectType", typeLit)} and lg.${tg("subjectId")} = x.${n("id")}::text
          and ${lifecycle.fn("retention_for")}(${kind}, ${tenant}) is not null
          and ${changed} < now() - ${lifecycle.fn("retention_for")}(${kind}, ${tenant})
          and not ${lifecycle.fn("is_held")}(${kind}, ${tenant})
      )
      and not ${fn("drive_node_held")}(x.${n("id")})
    order by ${changed}, x.${n("id")}
    limit ${pageSize("drive_retention_sweep.batch_size", 100, 1000)}
  loop
    begin
      perform ${fn("drive_trash")}(v_node);
      v_binned := v_binned + 1;
    exception when insufficient_privilege then
      null;
    end;
  end loop;
  return v_binned;
end;
$$;
${serviceGrant(`${fn("drive_retention_sweep")}(${ctx.idType}, integer)`)}
`;
}

/**
 * The changes feed: `updated_at` is the clock, so moving a node in or out of
 * the bin touches it, and a cursor is the last `updated_at` and id returned.
 */
export function driveChangesSql(kit: DriveKit): string {
  const {
    ctx,
    T,
    n,
    fn,
    read,
    canRead,
    withRole,
    forbidden,
    notFound,
    binColumn,
    driveColumn,
    roles,
  } = kit;

  if (!kit.has("updatedAt")) {
    return "";
  }

  const bin = binColumn
    ? `
-- Moving a node into the bin or back changes it for the feed and for retention.
create or replace function ${fn("drive_node_bin_touch")}()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.${n("deletedAt")} is distinct from old.${n("deletedAt")} then
    new.${n("updatedAt")} := now();
  end if;
  return new;
end;
$$;
drop trigger if exists ${ctx.trigger("drive_node_bin_touch")} on ${T};
create trigger ${ctx.trigger("drive_node_bin_touch")}
  before update of ${n("deletedAt")} on ${T}
  for each row execute function ${fn("drive_node_bin_touch")}();
`
    : "";

  const item = binColumn
    ? `case when v_row.${n("deletedAt")} is not null
        then jsonb_build_object('removed', true, 'id', v_row.${n("id")})
        else jsonb_build_object('removed', false, 'node', ${withRole("v_row")}) end`
    : `jsonb_build_object('removed', false, 'node', ${withRole("v_row")})`;

  return `${bin}
-- The nodes that changed after a cursor, oldest first, that the caller can
-- read. Changes from the last five seconds wait, so a transaction that
-- commits late isn't skipped.
create or replace function ${fn("drive_changes")}(tenant ${ctx.idType}, after text default null, page_size integer default 200, drive uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_at timestamptz;
  v_id uuid;
  v_size integer := ${pageSize("drive_changes.page_size", 200, 500)};
  v_row ${T}%rowtype;
  v_items jsonb := '[]'::jsonb;
  v_count integer := 0;
  v_more boolean := false;
  v_cursor text := drive_changes.after;
begin
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", "drive_changes.tenant", read)}) then
    ${forbidden("read this organization's drive")}
  end if;
  if drive_changes.after is not null then
    begin
      v_at := split_part(drive_changes.after, '|', 1)::timestamptz;
      v_id := split_part(drive_changes.after, '|', 2)::uuid;
    exception when others then
      ${fail("DRIVE_CURSOR_INVALID", "the changes cursor is not valid", "22023")}
    end;
  end if;${
    driveColumn
      ? `
  if drive_changes.drive is not null and not (${SERVICE_CALLER} or ${fn("drive_drive_can")}(drive_changes.drive, ${sqlString(roles.read)})) then
    ${notFound}
  end if;`
      : ""
  }
  for v_row in
    select * from ${T} x
    where x.${n("tenant")} = drive_changes.tenant
      and (v_at is null or (x.${n("updatedAt")}, x.${n("id")}) > (v_at, v_id))
      and x.${n("updatedAt")} <= now() - interval '5 seconds'${
        driveColumn
          ? `
      and (drive_changes.drive is null or x.${n("drive")} = drive_changes.drive)`
          : ""
      }
      and (${SERVICE_CALLER} or ${canRead(`x.${n("id")}`)})
    order by x.${n("updatedAt")}, x.${n("id")}
    limit v_size + 1
  loop
    v_count := v_count + 1;
    if v_count > v_size then
      v_more := true;
      exit;
    end if;
    v_items := v_items || jsonb_build_array(${item});
    v_cursor := to_char(v_row.${n("updatedAt")} at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') || '|' || v_row.${n("id")}::text;
  end loop;
  return jsonb_build_object('changes', v_items, 'cursor', v_cursor, 'more', v_more);
end;
$$;
${userGrant(`${fn("drive_changes")}(${ctx.idType}, text, integer, uuid)`)}
`;
}
