import type { BlockSqlContext } from "../context.ts";
import type { WarehouseSql } from "./warehouse-sql.ts";

import { sqlString } from "../../core/template.ts";
import { createdFromLink } from "../links.ts";
import { pageSize, userGrant } from "../shared.ts";
import { warehouseSql } from "./warehouse-sql.ts";

/** Whether the caller reads the list: a reader or the picker it is assigned to. */
function visible(q: WarehouseSql, row: string): string {
  return `coalesce(${q.allowed(`${row}.${q.p("tenant")}`, q.read)} or ${row}.${q.p("assignee")} = auth.uid(), false)`;
}

/**
 * Whether the caller may pick from the list: a picker it is assigned to, or a
 * manager.
 */
function pickable(q: WarehouseSql, row: string): string {
  return `(${q.allowed(`${row}.${q.p("tenant")}`, q.manage)} or (${q.allowed(`${row}.${q.p("tenant")}`, q.pick)} and coalesce(${row}.${q.p("assignee")} is null or ${row}.${q.p("assignee")} = auth.uid(), false)))`;
}

/** The json of a pick list with its lines. Not granted to anyone. */
function viewFunction(q: WarehouseSql): string {
  const { fn, p, l, lists, lines } = q;

  return `
-- The pick list as json, with its lines.
create or replace function ${fn("pick_list_json")}(pick_list_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', x.${p("id")}, 'organizationId', x.${p("tenant")}, 'waveId', x.${p("wave")},
    'locationId', x.${p("location")}, 'documentType', x.${p("documentType")}, 'documentId', x.${p("documentId")},
    'status', x.${p("status")}, 'assigneeId', x.${p("assignee")}, 'taskId', x.${p("task")},
    'pickedAt', x.${p("pickedAt")}, 'createdAt', x.${p("createdAt")},
    'lines', coalesce((
      select jsonb_agg(jsonb_build_object('id', y.${l("id")}, 'allocationId', y.${l("allocation")}, 'variantId', y.${l("variant")},
        'binId', y.${l("bin")}, 'lotId', y.${l("lot")}, 'serials', to_jsonb(y.${l("serials")}),
        'quantity', y.${l("quantity")}::text, 'picked', y.${l("picked")}::text, 'status', y.${l("status")},
        'pickedAt', y.${l("pickedAt")}, 'pickedBy', y.${l("pickedBy")})
        order by y.${l("variant")}, y.${l("id")})
      from ${lines} y where y.${l("list")} = x.${p("id")}
    ), '[]'::jsonb))
  from ${lists} x where x.${p("id")} = pick_list_json.pick_list_id
$$;
revoke execute on function ${fn("pick_list_json")}(uuid) from public, anon, authenticated;
`;
}

/** The work item for a pick list, when the tasks block is installed. */
function taskFunction(ctx: BlockSqlContext, q: WarehouseSql): string {
  const { tasks, fn, p, lists } = q;

  if (tasks === undefined) {
    return `
-- The tasks block isn't installed, so a pick list has no work item.
create or replace function ${fn("pick_list_task")}(pick_list_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  return;
end;
$$;
revoke execute on function ${fn("pick_list_task")}(uuid) from public, anon, authenticated;
`;
  }

  const link = createdFromLink(ctx, {
    tenant: `v_row.${p("tenant")}`,
    sourceType: sqlString(q.taskType),
    sourceId: "v_task::text",
    originType: q.subject,
    originId: `v_row.${p("id")}::text`,
  });

  return `
-- Makes the picker's work item for a pick list that has none. Creating it
-- needs the tasks permission of the caller. Not granted to anyone.
create or replace function ${fn("pick_list_task")}(pick_list_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${lists};
  v_task uuid;
begin
  select * into v_row from ${lists} x where x.${p("id")} = pick_list_task.pick_list_id and x.${p("task")} is null for update;
  if not found then
    return;
  end if;
  v_task := (${tasks.fn("create_task")}(v_row.${p("tenant")},
    jsonb_build_object('title', 'Pick ' || replace(v_row.${p("documentType")}, '_', ' ') || ' ' || v_row.${p("documentId")}),
    case when v_row.${p("assignee")} is null then '{}'::uuid[] else array[v_row.${p("assignee")}] end
  ) ->> 'id')::uuid;
  update ${lists} x set ${p("task")} = v_task where x.${p("id")} = v_row.${p("id")};
  ${link}
end;
$$;
revoke execute on function ${fn("pick_list_task")}(uuid) from public, anon, authenticated;
`;
}

function createFunctions(ctx: BlockSqlContext, q: WarehouseSql): string {
  const { fn, w, p, l, waves, lists, lines, inventory } = q;
  const idType = ctx.idType;
  const allocations = inventory.table("allocations");
  const buckets = inventory.table("buckets");
  const a = (column: string): string => inventory.col("allocations", column);
  const k = (column: string): string => inventory.col("buckets", column);

  return `
-- Creates a draft pick wave for a location. input is { name, locationId }.
-- Needs warehouse.manage.
create or replace function ${fn("create_pick_wave")}(tenant ${idType}, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${waves};
  v_name text;
  v_location uuid;
begin
  if not ${q.allowed("create_pick_wave.tenant", q.manage)} then
    ${q.forbidden("not allowed to manage pick waves")}
  end if;
  if jsonb_typeof(create_pick_wave.input) is distinct from 'object' then
    ${q.invalid("input must be an object")}
  end if;
  begin
    v_name := trim(create_pick_wave.input ->> 'name');
    v_location := (create_pick_wave.input ->> 'locationId')::uuid;
  exception when invalid_text_representation then
    ${q.invalid("locationId is a uuid")}
  end;
  if coalesce(length(v_name), 0) not between 1 and 200 then
    ${q.invalid("a wave needs a name of 1 to 200 characters")}
  end if;
  if not exists (select 1 from ${q.locations.table} x where x.${q.locations.col("id")} = v_location and x.${q.locations.col("tenant")} = create_pick_wave.tenant) then
    ${q.invalid("no such location in this organization")}
  end if;
  insert into ${waves} (${w("tenant")}, ${w("name")}, ${w("location")}, ${w("createdBy")})
  values (create_pick_wave.tenant, v_name, v_location, auth.uid())
  returning * into v_row;
  ${q.recordWave("pick_wave.created", "v_row", "pick wave created")}
  return ${q.waveJson("v_row")};
end;
$$;
${userGrant(`${fn("create_pick_wave")}(${idType}, jsonb)`)}

-- Makes a pick list from the open allocations of a document at a location.
-- input is { locationId, documentType, documentId, waveId, assigneeId }. A line
-- is made for each allocation that holds stock and is on no open pick line, and
-- starts with the bin and lot that hold the most of the variant. A list in a
-- draft wave waits for the wave's release; a list without a wave gets its work
-- item now. Needs warehouse.manage.
create or replace function ${fn("create_pick_list")}(tenant ${idType}, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${lists};
  v_wave ${waves};
  v_location uuid;
  v_type text;
  v_document text;
  v_wave_id uuid;
  v_assignee uuid;
  v_lines integer;
begin
  if not ${q.allowed("create_pick_list.tenant", q.manage)} then
    ${q.forbidden("not allowed to manage pick lists")}
  end if;
  if jsonb_typeof(create_pick_list.input) is distinct from 'object' then
    ${q.invalid("input must be an object")}
  end if;
  begin
    v_location := (create_pick_list.input ->> 'locationId')::uuid;
    v_type := trim(create_pick_list.input ->> 'documentType');
    v_document := trim(create_pick_list.input ->> 'documentId');
    v_wave_id := nullif(create_pick_list.input ->> 'waveId', '')::uuid;
    v_assignee := nullif(create_pick_list.input ->> 'assigneeId', '')::uuid;
  exception when invalid_text_representation then
    ${q.invalid("locationId, waveId and assigneeId are uuids")}
  end;
  if v_type is null or v_type !~ '^[a-z][a-z0-9_]{0,62}$' or coalesce(length(v_document), 0) not between 1 and 200 then
    ${q.invalid("a pick list needs a documentType in snake_case and a documentId")}
  end if;
  if not exists (select 1 from ${q.locations.table} x where x.${q.locations.col("id")} = v_location and x.${q.locations.col("tenant")} = create_pick_list.tenant) then
    ${q.invalid("no such location in this organization")}
  end if;
  if v_wave_id is not null then
    select * into v_wave from ${waves} x
    where x.${w("id")} = v_wave_id and x.${w("tenant")} = create_pick_list.tenant for update;
    if not found then
      ${q.waveMissing}
    end if;
    if v_wave.${w("status")} <> 'draft' or v_wave.${w("location")} <> v_location then
      ${q.state("a list joins a draft wave of the same location")}
    end if;
  end if;
  ${ctx.hook("before_pick_list_create", [
    [idType, "create_pick_list.tenant"],
    ["jsonb", "create_pick_list.input"],
  ])}
  insert into ${lists} (${p("tenant")}, ${p("wave")}, ${p("location")}, ${p("documentType")}, ${p("documentId")}, ${p("assignee")}, ${p("createdBy")})
  values (create_pick_list.tenant, v_wave_id, v_location, v_type, v_document, v_assignee, auth.uid())
  returning * into v_row;
  insert into ${lines} (${l("tenant")}, ${l("list")}, ${l("allocation")}, ${l("variant")}, ${l("bin")}, ${l("lot")}, ${l("quantity")})
  select v_row.${p("tenant")}, v_row.${p("id")}, x.${a("id")}, x.${a("variant")}, b.bin, b.lot, x.${a("allocated")}
  from ${allocations} x
  left join lateral (
    select y.${k("bin")} as bin, y.${k("lot")} as lot
    from ${buckets} y
    where y.${k("variant")} = x.${a("variant")} and y.${k("location")} = x.${a("location")} and y.${k("onHand")} > 0
    order by y.${k("onHand")} desc, y.${k("lot")} nulls last, y.${k("bin")} nulls last
    limit 1
  ) b on true
  where x.${a("tenant")} = v_row.${p("tenant")} and x.${a("location")} = v_location
    and x.${a("documentType")} = v_type and x.${a("documentId")} = v_document
    and x.${a("status")} = 'open' and x.${a("allocated")} > 0
    and not exists (select 1 from ${lines} z where z.${l("allocation")} = x.${a("id")} and z.${l("status")} = 'open');
  get diagnostics v_lines = row_count;
  if v_lines = 0 then
    ${q.state("the document has no allocated stock left to pick at this location")}
  end if;
  if v_row.${p("wave")} is null then
    perform ${fn("pick_list_task")}(v_row.${p("id")});
  end if;
  ${q.recordList("pick_list.created", "v_row", "pick list created", ", 'lines', v_lines")}
  ${ctx.hook("after_pick_list_create", [["uuid", `v_row.${p("id")}`]])}
  return ${fn("pick_list_json")}(v_row.${p("id")});
end;
$$;
${userGrant(`${fn("create_pick_list")}(${idType}, jsonb)`)}

-- Releases a draft wave: its pick lists become work items for the pickers and
-- can be picked. Needs warehouse.manage.
create or replace function ${fn("release_pick_wave")}(wave_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${waves};
  v_list uuid;
begin
  select * into v_row from ${waves} x where x.${w("id")} = release_pick_wave.wave_id for update;
  if not found then
    ${q.waveMissing}
  end if;
  if not ${q.allowed(`v_row.${w("tenant")}`, q.manage)} then
    ${q.forbidden("not allowed to manage pick waves")}
  end if;
  if v_row.${w("status")} <> 'draft' then
    ${q.state("only a draft wave is released")}
  end if;
  if not exists (select 1 from ${lists} x where x.${p("wave")} = v_row.${w("id")} and x.${p("status")} = 'open') then
    ${q.state("a wave needs a pick list before it is released")}
  end if;
  for v_list in select x.${p("id")} from ${lists} x where x.${p("wave")} = v_row.${w("id")} and x.${p("status")} = 'open' order by x.${p("createdAt")}, x.${p("id")} loop
    perform ${fn("pick_list_task")}(v_list);
  end loop;
  update ${waves} x set ${w("status")} = 'released', ${w("releasedAt")} = now()
  where x.${w("id")} = v_row.${w("id")}
  returning * into v_row;
  ${q.recordWave("pick_wave.released", "v_row", "pick wave released")}
  return ${q.waveJson("v_row")};
end;
$$;
${userGrant(`${fn("release_pick_wave")}(uuid)`)}

-- Cancels a draft or released wave with its open pick lists and lines. What
-- was picked stays recorded on the lines. Needs warehouse.manage.
create or replace function ${fn("cancel_pick_wave")}(wave_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${waves};
begin
  select * into v_row from ${waves} x where x.${w("id")} = cancel_pick_wave.wave_id for update;
  if not found then
    ${q.waveMissing}
  end if;
  if not ${q.allowed(`v_row.${w("tenant")}`, q.manage)} then
    ${q.forbidden("not allowed to manage pick waves")}
  end if;
  if v_row.${w("status")} not in ('draft', 'released') then
    ${q.state("only a draft or released wave is cancelled")}
  end if;
  update ${lines} y set ${l("status")} = 'cancelled'
  from ${lists} x
  where y.${l("list")} = x.${p("id")} and x.${p("wave")} = v_row.${w("id")} and x.${p("status")} = 'open' and y.${l("status")} = 'open';
  update ${lists} x set ${p("status")} = 'cancelled' where x.${p("wave")} = v_row.${w("id")} and x.${p("status")} = 'open';
  update ${waves} x set ${w("status")} = 'cancelled' where x.${w("id")} = v_row.${w("id")}
  returning * into v_row;
  return ${q.waveJson("v_row")};
end;
$$;
${userGrant(`${fn("cancel_pick_wave")}(uuid)`)}
`;
}

function pickFunctions(q: WarehouseSql): string {
  const { fn, w, p, l, waves, lists, lines, inventory } = q;
  const bins = inventory.table("bins");
  const lots = inventory.table("lots");
  const b = (column: string): string => inventory.col("bins", column);
  const t = (column: string): string => inventory.col("lots", column);

  return `
-- Records what a picker found for a line of an open pick list. attrs is
-- { quantity, binId, lotId, serials }: quantity is added to what was picked,
-- and the bin, lot and serial numbers replace the suggestion when given. A line
-- is picked once its quantity is. The stock stays where it is until the
-- document ships. Needs warehouse.pick on a list assigned to the caller or to
-- nobody, or warehouse.manage.
create or replace function ${fn("record_pick")}(line_id uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_line ${lines};
  v_list ${lists};
  v_wave_status text;
  v_quantity numeric;
  v_bin uuid;
  v_lot uuid;
  v_serials text[];
begin
  select * into v_line from ${lines} x where x.${l("id")} = record_pick.line_id for update;
  if not found then
    ${q.lineMissing}
  end if;
  select * into v_list from ${lists} x where x.${p("id")} = v_line.${l("list")};
  if not coalesce(${pickable(q, "v_list")}, false) then
    ${q.forbidden("not allowed to pick from this list")}
  end if;
  if jsonb_typeof(record_pick.attrs) is distinct from 'object' then
    ${q.invalid("attrs must be an object")}
  end if;
  begin
    v_quantity := (record_pick.attrs ->> 'quantity')::numeric;
    v_bin := nullif(record_pick.attrs ->> 'binId', '')::uuid;
    v_lot := nullif(record_pick.attrs ->> 'lotId', '')::uuid;
    if jsonb_typeof(record_pick.attrs -> 'serials') = 'array' then
      v_serials := array(select jsonb_array_elements_text(record_pick.attrs -> 'serials'));
    end if;
  exception when invalid_text_representation then
    ${q.invalid("quantity is a number and binId and lotId are uuids")}
  end;
  if v_list.${p("status")} <> 'open' or v_line.${l("status")} <> 'open' then
    ${q.state("the pick list or the line is no longer open")}
  end if;
  if v_list.${p("wave")} is not null then
    select x.${w("status")} into v_wave_status from ${waves} x where x.${w("id")} = v_list.${p("wave")};
    if v_wave_status <> 'released' then
      ${q.state("the wave isn't released yet")}
    end if;
  end if;
  if v_quantity is null or v_quantity <= 0 or v_quantity > v_line.${l("quantity")} - v_line.${l("picked")} then
    ${q.invalid("the quantity must be more than zero and at most what is left to pick")}
  end if;
  if v_bin is not null and not exists (select 1 from ${bins} x where x.${b("id")} = v_bin and x.${b("tenant")} = v_line.${l("tenant")}) then
    ${q.invalid("no such bin in this organization")}
  end if;
  if v_lot is not null and not exists (select 1 from ${lots} x where x.${t("id")} = v_lot and x.${t("tenant")} = v_line.${l("tenant")}) then
    ${q.invalid("no such lot in this organization")}
  end if;
  update ${lines} x set
    ${l("picked")} = x.${l("picked")} + v_quantity,
    ${l("bin")} = coalesce(v_bin, x.${l("bin")}),
    ${l("lot")} = coalesce(v_lot, x.${l("lot")}),
    ${l("serials")} = coalesce(v_serials, x.${l("serials")}),
    ${l("status")} = case when x.${l("picked")} + v_quantity >= x.${l("quantity")} then 'picked' else 'open' end,
    ${l("pickedAt")} = now(),
    ${l("pickedBy")} = auth.uid()
  where x.${l("id")} = v_line.${l("id")};
  return ${fn("pick_list_json")}(v_list.${p("id")});
end;
$$;
${userGrant(`${fn("record_pick")}(uuid, jsonb)`)}

-- Finishes a pick list: a line with less picked than asked for becomes short.
-- When it was the last open list of its wave, the wave completes. Needs the
-- same permission as record_pick.
create or replace function ${fn("complete_pick_list")}(pick_list_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_list ${lists};
  v_wave ${waves};
  v_short integer;
begin
  select * into v_list from ${lists} x where x.${p("id")} = complete_pick_list.pick_list_id for update;
  if not found then
    ${q.listMissing}
  end if;
  if not coalesce(${pickable(q, "v_list")}, false) then
    ${q.forbidden("not allowed to pick from this list")}
  end if;
  if v_list.${p("status")} <> 'open' then
    ${q.state("only an open pick list is completed")}
  end if;
  if v_list.${p("wave")} is not null and (select x.${w("status")} from ${waves} x where x.${w("id")} = v_list.${p("wave")}) <> 'released' then
    ${q.state("the wave isn't released yet")}
  end if;
  update ${lines} y set ${l("status")} = case when y.${l("picked")} >= y.${l("quantity")} then 'picked' else 'short' end
  where y.${l("list")} = v_list.${p("id")} and y.${l("status")} = 'open';
  select count(*) into v_short from ${lines} y where y.${l("list")} = v_list.${p("id")} and y.${l("status")} = 'short';
  update ${lists} x set ${p("status")} = 'picked', ${p("pickedAt")} = now()
  where x.${p("id")} = v_list.${p("id")}
  returning * into v_list;
  ${q.recordList("pick_list.picked", "v_list", "pick list completed", ", 'short', v_short")}
  if v_list.${p("wave")} is not null and not exists (select 1 from ${lists} x where x.${p("wave")} = v_list.${p("wave")} and x.${p("status")} = 'open') then
    update ${waves} x set ${w("status")} = 'completed', ${w("completedAt")} = now()
    where x.${w("id")} = v_list.${p("wave")} and x.${w("status")} = 'released'
    returning * into v_wave;
    if v_wave.${w("id")} is not null then
      ${q.recordWave("pick_wave.completed", "v_wave", "pick wave completed")}
    end if;
  end if;
  return ${fn("pick_list_json")}(v_list.${p("id")});
end;
$$;
${userGrant(`${fn("complete_pick_list")}(uuid)`)}
`;
}

function readFunctions(ctx: BlockSqlContext, q: WarehouseSql): string {
  const { fn, w, p, waves, lists } = q;
  const idType = ctx.idType;

  return `
-- A pick list with its lines. Readers see every list; a picker sees the lists
-- assigned to them.
create or replace function ${fn("get_pick_list")}(pick_list_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${lists};
begin
  select * into v_row from ${lists} x where x.${p("id")} = get_pick_list.pick_list_id;
  if not found or not ${visible(q, "v_row")} then
    ${q.listMissing}
  end if;
  return ${fn("pick_list_json")}(v_row.${p("id")});
end;
$$;
${userGrant(`${fn("get_pick_list")}(uuid)`)}

-- Pick lists of an organization, newest first. filters is { waveId, status,
-- documentType, documentId, mine: true, limit, offset }. Readers see all of
-- them; everyone else sees the lists assigned to them.
create or replace function ${fn("list_pick_lists")}(tenant ${idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_pick_lists.filters, '{}'::jsonb);
  v_limit integer := ${pageSize("(v_filters ->> 'limit')::integer", 50, 200)};
  v_all boolean := ${q.allowed("list_pick_lists.tenant", q.read)};
begin
  return coalesce((
    select jsonb_agg(${fn("pick_list_json")}(y.id) order by y.created_at desc, y.id)
    from (
      select x.${p("id")} as id, x.${p("createdAt")} as created_at
      from ${lists} x
      where x.${p("tenant")} = list_pick_lists.tenant
        and (not v_filters ? 'waveId' or x.${p("wave")} = (v_filters ->> 'waveId')::uuid)
        and (not v_filters ? 'status' or x.${p("status")} = v_filters ->> 'status')
        and (not v_filters ? 'documentType' or x.${p("documentType")} = v_filters ->> 'documentType')
        and (not v_filters ? 'documentId' or x.${p("documentId")} = v_filters ->> 'documentId')
        and ((v_all and (v_filters ->> 'mine') is distinct from 'true') or coalesce(x.${p("assignee")} = auth.uid(), false))
      order by x.${p("createdAt")} desc, x.${p("id")}
      limit v_limit offset coalesce((v_filters ->> 'offset')::integer, 0)
    ) y
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_pick_lists")}(${idType}, jsonb)`)}

-- The pick waves of an organization, newest first, with how many lists each
-- has and how many are still open. Needs warehouse.read.
create or replace function ${fn("list_pick_waves")}(tenant ${idType})
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not ${q.allowed("list_pick_waves.tenant", q.read)} then
    ${q.forbidden("not allowed to read pick waves")}
  end if;
  return coalesce((
    select jsonb_agg(${q.waveJson("x")}
      || jsonb_build_object(
        'lists', (select count(*) from ${lists} z where z.${p("wave")} = x.${w("id")} and z.${p("status")} <> 'cancelled'),
        'openLists', (select count(*) from ${lists} z where z.${p("wave")} = x.${w("id")} and z.${p("status")} = 'open'))
      order by x.${w("createdAt")} desc, x.${w("id")})
    from ${waves} x where x.${w("tenant")} = list_pick_waves.tenant
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_pick_waves")}(${idType})`)}
`;
}

export function warehousePicking(ctx: BlockSqlContext): string {
  const q = warehouseSql(ctx);

  return `${viewFunction(q)}${taskFunction(ctx, q)}${createFunctions(ctx, q)}${pickFunctions(q)}${readFunctions(ctx, q)}`;
}
