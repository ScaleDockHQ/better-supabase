import type { DriveKit } from "./drive-kit.ts";

import { fail, SERVICE_CALLER, userGrant } from "../shared.ts";

/** Legal holds: placing and releasing them on a node and its subtree. */
export function driveHoldsSql(kit: DriveKit): string {
  const {
    T,
    n,
    fn,
    live,
    canRead,
    canShare,
    readOnly,
    notFound,
    forbidden,
    touch,
    record,
    dataAudit,
    withRole,
    holdColumn,
  } = kit;

  return holdColumn
    ? `
-- Places a legal hold on a node and everything under it: purge skips held
-- nodes until the hold ends or is released.
create or replace function ${fn("drive_hold")}(node uuid, until timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node ${T}%rowtype;
begin
  select * into v_node from ${T} x where x.${n("id")} = drive_hold.node${live("x")} for update;
  if not found or not (${SERVICE_CALLER} or ${canRead(`v_node.${n("id")}`)}) then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or ${canShare(`v_node.${n("id")}`)}) then
    ${forbidden("place a legal hold")}
  end if;
  if ${readOnly("v_node")} then
    ${fail("DRIVE_READ_ONLY", "this item mirrors an external account and is read-only", "42501")}
  end if;
  if drive_hold.until is null or drive_hold.until <= now() then
    ${fail("DRIVE_HOLD_INVALID", "a legal hold needs an end in the future", "22023")}
  end if;
  update ${T} x set ${n("legalHoldUntil")} = drive_hold.until${touch}
  where x.${n("id")} = v_node.${n("id")}
  returning * into v_node;
  ${record("drive.node_hold_placed", "v_node", `, 'legalHoldUntil', v_node.${n("legalHoldUntil")}`, dataAudit("v_node", "held"))}
  return ${withRole("v_node")};
end;
$$;
${userGrant(`${fn("drive_hold")}(uuid, timestamptz)`)}

create or replace function ${fn("drive_release_hold")}(node uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node ${T}%rowtype;
begin
  select * into v_node from ${T} x where x.${n("id")} = drive_release_hold.node${live("x")} for update;
  if not found or not (${SERVICE_CALLER} or ${canRead(`v_node.${n("id")}`)}) then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or ${canShare(`v_node.${n("id")}`)}) then
    ${forbidden("release a legal hold")}
  end if;
  if ${readOnly("v_node")} then
    ${fail("DRIVE_READ_ONLY", "this item mirrors an external account and is read-only", "42501")}
  end if;
  update ${T} x set ${n("legalHoldUntil")} = null${touch}
  where x.${n("id")} = v_node.${n("id")}
  returning * into v_node;
  ${record("drive.node_hold_released", "v_node", "", dataAudit("v_node", "released"))}
  return ${withRole("v_node")};
end;
$$;
${userGrant(`${fn("drive_release_hold")}(uuid)`)}
`
    : "";
}
