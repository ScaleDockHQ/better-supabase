import type { BlockSqlContext } from "../context.ts";
import type { TaskNames } from "./tasks-functions.ts";

import { sqlString } from "../../core/template.ts";
import { fail, serviceGrant, userGrant } from "../shared.ts";
import {
  load,
  stageByCategory,
  stageRef,
  stageRefLabel,
  taskRecord,
} from "./tasks-coordination-shared.ts";
import { cancelHoldRequestSql, HOLD_SUBJECT } from "./tasks-hold-approvals.ts";

/** Claims: claim, claim next, renew, release, delegate and the expiry job. */
export function claimsSql(
  ctx: BlockSqlContext,
  n: TaskNames,
  h: { readonly row: (alias: string) => string },
): string {
  if (!ctx.hasTable("claims")) {
    return "";
  }

  const { fn, t, co } = { fn: n.fn, t: n.t, co: n.co };
  const w = (column: string): string => n.c("items", column);
  const k = (column: string): string => n.c("claims", column);
  const a = (column: string): string => n.c("assignees", column);
  const has = (logical: string): boolean => ctx.has("items", logical);
  const e = n.e;

  const live = (alias: string): string => `${alias}.${k("expiresAt")} > now()`;

  const claimJson = (alias: string, token: boolean): string =>
    `jsonb_build_object(${token ? `'token', ${alias}.${k("token")}, ` : ""}'epoch', ${alias}.${k("epoch")}, 'holderId', ${alias}.${k("holder")}, 'profile', ${alias}.${k("profile")}, 'claimedAt', ${alias}.${k("claimedAt")}, 'expiresAt', ${alias}.${k("expiresAt")})`;

  const claimEventExtra = (alias: string): string =>
    `, 'holderId', ${alias}.${k("holder")}, 'epoch', ${alias}.${k("epoch")}, 'expiresAt', ${alias}.${k("expiresAt")}`;

  const startStage =
    co.startStage === null
      ? ""
      : `
  if v_row.${w("pipeline")} is not null then
    update ${t("items")} x set ${w("stage")} = ${stageRef(ctx, `v_row.${w("pipeline")}`, co.startStage)}
    where x.${w("id")} = v_row.${w("id")} and x.${w("stage")} is distinct from ${stageRef(ctx, `v_row.${w("pipeline")}`, co.startStage)}
      and ${stageRef(ctx, `v_row.${w("pipeline")}`, co.startStage)} is not null;
  end if;`;

  const needsGuard =
    co.needs !== null && co.needs.refuse !== "none"
      ? `
  if v_row.${w("waitingOn")} > 0 then
    ${fail("TASK_NOT_READY", "the task waits on prerequisites that aren't completed", "55000")}
  end if;`
      : "";

  const heldGuard = has("heldAt")
    ? `
  if v_row.${w("heldAt")} is not null then
    ${fail("TASK_HELD", "the task is on hold", "55000")}
  end if;`
    : "";

  const filter = (alias: string): string => `
      and (claim_next_task.filter ->> 'teamId' is null or ${alias}.${w("team")} = (claim_next_task.filter ->> 'teamId')::uuid)
      and (claim_next_task.filter ->> ${sqlString(e("projectId"))} is null or ${has("project") ? `${alias}.${w("project")} = (claim_next_task.filter ->> ${sqlString(e("projectId"))})::uuid` : "false"})
      and (claim_next_task.filter ->> 'parentId' is null or ${alias}.${w("parent")} = (claim_next_task.filter ->> 'parentId')::uuid)
      and (claim_next_task.filter ->> 'stageId' is null or ${alias}.${w("stage")} = (claim_next_task.filter ->> 'stageId')::uuid)
      and (claim_next_task.filter ->> 'assigneeId' is null or exists (select 1 from ${t("assignees")} y where y.${a("item")} = ${alias}.${w("id")} and y.${a("user")} = (claim_next_task.filter ->> 'assigneeId')::uuid))`;

  const isAgent = `coalesce(auth.jwt() -> 'act' ->> 'kind' = 'agent', false)`;
  const restricted = `(${isAgent}${co.next === "assigned" ? " or auth.uid() is not null" : ""})`;

  // An agent acts with a member's access, so it never picks beyond that
  // member's own tasks, whatever claims.next says.
  const mine = (alias: string): string =>
    `exists (select 1 from ${t("assignees")} y where y.${a("item")} = ${alias}.${w("id")} and y.${a("user")} = auth.uid())`;

  const agentGuard = `
  if ${isAgent} and not ${mine("v_row")} then
    ${fail("TASK_NOT_ASSIGNED", "an agent session claims only tasks assigned to its user", "42501")}
  end if;`;

  const assignedOnly = `
  if ${restricted} then
    if claim_next_task.filter ->> 'assigneeId' is not null and (claim_next_task.filter ->> 'assigneeId')::uuid is distinct from auth.uid() then
      ${fail("TASK_FILTER_FORBIDDEN", "this session picks only its own tasks", "42501")}
    end if;
  end if;`;

  const leaseOf = (lease: string): string =>
    `least(${String(co.maxLease)}, greatest(1, coalesce(${lease}, ${String(co.lease)})))`;

  const delegateProfile = has("delegateProfile")
    ? `, ${w("delegateProfile")} = v_actor`
    : "";

  return `

-- Takes the lease on a task. Returns { task, claim } with the claim's token,
-- which renew and release need. A live claim of someone else raises
-- TASK_CLAIMED; the same holder claiming again keeps the token. A task that
-- waits on prerequisites raises TASK_NOT_READY (with the needs option), a held
-- one TASK_HELD, a closed one TASK_CLOSED.
create or replace function ${fn("claim_task")}(task uuid, lease integer default null, profile jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("items")};
  v_claim ${t("claims")};
  v_actor jsonb := ${fn("task_actor")}(claim_task.profile);
begin
  ${load(ctx, n, "claim_task", co.claim)}
  if v_row.${w("closedAt")} is not null then
    ${fail("TASK_CLOSED", "a closed task can't be claimed", "55000")}
  end if;${agentGuard}${heldGuard}${needsGuard}
  insert into ${t("claims")} as c (${k("task")}, ${k("tenant")}, ${k("holder")}, ${k("profile")}, ${k("expiresAt")})
  values (v_row.${w("id")}, v_row.${w("tenant")}, auth.uid(), v_actor, now() + make_interval(secs => ${leaseOf("claim_task.lease")}))
  on conflict (${k("task")}) do update set
    ${k("token")} = case when ${live("c")} then c.${k("token")} else gen_random_uuid() end,
    ${k("epoch")} = case when ${live("c")} then c.${k("epoch")} else c.${k("epoch")} + 1 end,
    ${k("holder")} = excluded.${k("holder")},
    ${k("profile")} = excluded.${k("profile")},
    ${k("claimedAt")} = case when ${live("c")} then c.${k("claimedAt")} else now() end,
    ${k("expiresAt")} = excluded.${k("expiresAt")},
    ${k("expiredAt")} = null
  where not ${live("c")}
    or (c.${k("holder")} is not distinct from excluded.${k("holder")} and c.${k("profile")} ->> 'name' is not distinct from excluded.${k("profile")} ->> 'name')
  returning * into v_claim;
  if not found then
    ${fail("TASK_CLAIMED", "another holder has a live claim on the task", "55P03")}
  end if;${startStage}
  ${taskRecord(ctx, n, "task.claimed", "v_row", claimEventExtra("v_claim"), "claim_task.profile")}
  return jsonb_build_object('task', (select ${h.row("x")} from ${t("items")} x where x.${w("id")} = v_row.${w("id")}), 'claim', ${claimJson("v_claim", true)});
end;
$$;
${userGrant(`${fn("claim_task")}(uuid, integer, jsonb)`)}

-- Claims the next ready task of a tenant: assigned to you first, then the
-- lowest number. With claims.next "assigned" (the default) and for an agent
-- session, only tasks assigned to you qualify. filter narrows the pick: teamId, ${e("projectId")}, parentId, stageId,
-- assigneeId. Concurrent callers skip each other's rows. Raises
-- TASK_NOTHING_READY when no task qualifies.
create or replace function ${fn("claim_next_task")}(tenant ${ctx.idType}, filter jsonb default null, lease integer default null, profile jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    ${fail("ACTOR_READ_ONLY", "This session is read-only")}
  end if;
${assignedOnly}
  if not (${n.service} or ${ctx.scope.can("claim_next_task.tenant", co.claim)}) then
    ${fail("TASK_FORBIDDEN", "not allowed to claim work items")}
  end if;
  select x.${w("id")} into v_id from ${t("items")} x
  where x.${w("tenant")} = claim_next_task.tenant and x.${w("archivedAt")} is null and x.${w("closedAt")} is null${n.templates ? `\n    and x.${w("template")} is null` : ""}${has("heldAt") ? `\n    and x.${w("heldAt")} is null` : ""}${co.needs === null ? "" : `\n    and x.${w("waitingOn")} = 0`}
    and (not ${restricted} or ${mine("x")})
    and not exists (select 1 from ${t("claims")} c where c.${k("task")} = x.${w("id")} and ${live("c")})${filter("x")}
  order by (case when exists (select 1 from ${t("assignees")} y where y.${a("item")} = x.${w("id")} and y.${a("user")} = auth.uid()) then 0 else 1 end), x.${w("number")}
  limit 1
  for update of x skip locked;
  if v_id is null then
    ${fail("TASK_NOTHING_READY", "no task is ready to claim", "P0002")}
  end if;
  return ${fn("claim_task")}(v_id, claim_next_task.lease, claim_next_task.profile);
end;
$$;
${userGrant(`${fn("claim_next_task")}(${ctx.idType}, jsonb, integer, jsonb)`)}

-- Extends a live claim to now plus the lease. Raises TASK_CLAIM_LOST when the
-- token isn't the live claim's, because the lease ran out or someone took over.
create or replace function ${fn("renew_task_claim")}(task uuid, token uuid, lease integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claim ${t("claims")};
begin
  update ${t("claims")} c set ${k("expiresAt")} = now() + make_interval(secs => ${leaseOf("renew_task_claim.lease")})
  where c.${k("task")} = renew_task_claim.task and c.${k("token")} = renew_task_claim.token and ${live("c")}
    and (${n.service} or ${ctx.scope.can(`c.${k("tenant")}`, co.claim)})
  returning * into v_claim;
  if not found then
    ${fail("TASK_CLAIM_LOST", "the claim ran out or another holder took over", "55000")}
  end if;
  return ${claimJson("v_claim", true)};
end;
$$;
${userGrant(`${fn("renew_task_claim")}(uuid, uuid, integer)`)}

-- Gives a claim up. Raises TASK_CLAIM_NOT_HELD when nobody holds the task and
-- TASK_CLAIM_LOST when the token isn't the live claim's.
create or replace function ${fn("release_task_claim")}(task uuid, token uuid, note text default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claim ${t("claims")};
  v_row ${t("items")};
begin
  select * into v_claim from ${t("claims")} c where c.${k("task")} = release_task_claim.task for update;
  if not found then
    ${fail("TASK_CLAIM_NOT_HELD", "nobody holds this task", "P0002")}
  end if;
  if v_claim.${k("token")} is distinct from release_task_claim.token or not (v_claim.${k("expiresAt")} > now()) then
    ${fail("TASK_CLAIM_LOST", "the claim ran out or another holder took over", "55000")}
  end if;
  update ${t("claims")} c set ${k("expiresAt")} = now(), ${k("expiredAt")} = now() where c.${k("task")} = release_task_claim.task;
  select * into v_row from ${t("items")} x where x.${w("id")} = release_task_claim.task;
  ${taskRecord(ctx, n, "task.released", "v_row", `${claimEventExtra("v_claim")}, 'note', nullif(trim(release_task_claim.note), '')`, `v_claim.${k("profile")}`)}
  return true;
end;
$$;
${userGrant(`${fn("release_task_claim")}(uuid, uuid, text)`)}

-- Hands a task to a user: assigns them, notes who delegated, and drops a claim
-- held by someone else. The user needs tasks.read in the organization.
create or replace function ${fn("delegate_task")}(task uuid, to_user uuid, profile jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("items")};
  v_actor jsonb := ${fn("task_actor")}(delegate_task.profile);
  v_added boolean;
begin
  ${load(ctx, n, "delegate_task", n.write)}
  if not ${ctx.scope.canUser("delegate_task.to_user", `v_row.${w("tenant")}`, n.read)} then
    ${fail("TASK_DELEGATE_INVALID", "the user can't read tasks in this organization", "22023")}
  end if;
  insert into ${t("assignees")} (${a("tenant")}, ${a("item")}, ${a("user")}) values (v_row.${w("tenant")}, v_row.${w("id")}, delegate_task.to_user)
  on conflict do nothing;
  v_added := found;
  delete from ${t("claims")} c where c.${k("task")} = v_row.${w("id")} and c.${k("holder")} is distinct from delegate_task.to_user;${
    delegateProfile === ""
      ? ""
      : `
  update ${t("items")} x set ${delegateProfile.slice(2)} where x.${w("id")} = v_row.${w("id")};`
  }
  ${taskRecord(ctx, n, "task.delegated", "v_row", ", 'delegateId', delegate_task.to_user", "delegate_task.profile")}
  if v_added then
    ${taskRecord(ctx, n, "task.assigned", "v_row", `, 'assigneeIds', to_jsonb(array(select y.${a("user")} from ${t("assignees")} y where y.${a("item")} = v_row.${w("id")})), 'addedIds', jsonb_build_array(delegate_task.to_user)`)}
  end if;
  return (select ${h.row("x")} from ${t("items")} x where x.${w("id")} = v_row.${w("id")});
end;
$$;
${userGrant(`${fn("delegate_task")}(uuid, uuid, jsonb)`)}

-- Deletes the claims whose lease ran out, moves each task to the expired stage
-- (the claims.expiredStage option) and records task.claim_expired.
create or replace function ${fn("expire_task_claims")}()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claim ${t("claims")};
  v_row ${t("items")};
  v_count integer := 0;
begin
  for v_claim in update ${t("claims")} c set ${k("expiredAt")} = now() where c.${k("expiresAt")} <= now() and c.${k("expiredAt")} is null returning c.* loop
    v_count := v_count + 1;
    select * into v_row from ${t("items")} x where x.${w("id")} = v_claim.${k("task")};
    if found and v_row.${w("closedAt")} is null then${
      co.expiredStage === null
        ? ""
        : `
      if v_row.${w("pipeline")} is not null and ${stageRef(ctx, `v_row.${w("pipeline")}`, co.expiredStage)} is not null then
        update ${t("items")} x set ${w("stage")} = ${stageRef(ctx, `v_row.${w("pipeline")}`, co.expiredStage)} where x.${w("id")} = v_row.${w("id")} and x.${w("stage")} is distinct from ${stageRef(ctx, `v_row.${w("pipeline")}`, co.expiredStage)}
        returning * into v_row;
      end if;`
    }
      ${taskRecord(ctx, n, "task.claim_expired", "v_row", `${claimEventExtra("v_claim")}, 'returnStageId', v_row.${w("stage")}`, `v_claim.${k("profile")}`)}
    end if;
  end loop;
  return v_count;
end;
$$;
${serviceGrant(`${fn("expire_task_claims")}()`)}
`;
}

/** Holds: a task waits on someone, with a note that reaches them. */
export function holdSql(
  ctx: BlockSqlContext,
  n: TaskNames,
  h: { readonly row: (alias: string) => string },
): string {
  const { fn, t, co } = { fn: n.fn, t: n.t, co: n.co };
  const w = (column: string): string => n.c("items", column);
  const k = (column: string): string => n.c("claims", column);
  const flag = ctx.has("items", "heldAt");
  const kind = ctx.has("items", "holdKind");
  const type = sqlString(n.type);

  if (!flag && co.holdStage === null) {
    return `
create or replace function ${fn("hold_task")}(task uuid, kind text, note text default null, ask_user_ids uuid[] default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  ${fail("TASK_FIELD_UNSUPPORTED", `this ${ctx.tableName("items").name} table has no held_at column and the hold option names no stage`, "22023")}
end;
$$;
${userGrant(`${fn("hold_task")}(uuid, text, text, uuid[])`)}

create or replace function ${fn("release_task_hold")}(task uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  ${fail("TASK_FIELD_UNSUPPORTED", `this ${ctx.tableName("items").name} table has no held_at column and the hold option names no stage`, "22023")}
end;
$$;
${userGrant(`${fn("release_task_hold")}(uuid)`)}
`;
  }

  const approval = co.holdApproval;

  const open =
    approval === null
      ? ""
      : `
${approval.kinds === null ? "" : `  if hold_task.kind = any(array[${approval.kinds.map((kind) => sqlString(kind)).join(", ")}]) then\n  `}  v_request := ${ctx.of("approvals").fn("open_approval")}(v_row.${w("tenant")}, ${sqlString(HOLD_SUBJECT)}, v_row.${w("id")}::text, 'approve',
    ${sqlString(approval.policy)}::jsonb, v_note, jsonb_build_object('kind', hold_task.kind), auth.uid());${approval.kinds === null ? "" : "\n  end if;"}`;

  const messaging = ctx.installed("messaging")
    ? (() => {
        const m = ctx.of("messaging");

        return `
  if v_note is not null or cardinality(v_ask) > 0 then
    v_conversation := (${m.fn("open_conversation")}(v_row.${w("tenant")}, 'subject', jsonb_build_object('subjectType', ${type}, 'subjectId', v_row.${w("id")}::text), '{}'))
      ->> 'id';
    perform ${m.fn("send_message")}(v_conversation::uuid, coalesce(v_note, 'On hold: ' || hold_task.kind),
      jsonb_build_object('mentions', to_jsonb(v_ask)), '{}');
  end if;`;
      })()
    : `
  if cardinality(v_ask) > 0 then
    ${fail("TASK_HOLD_MESSAGING_MISSING", "asking people needs the messaging block", "22023")}
  end if;`;

  const moveIn =
    co.holdStage === null
      ? ""
      : `
  v_stage := ${stageRef(ctx, `v_row.${w("pipeline")}`, co.holdStage)};
  if v_stage is null then
    ${fail("TASK_HOLD_STAGE_MISSING", `the task's pipeline has no ${stageRefLabel(co.holdStage)}`, "22023")}
  end if;`;

  const sets = [
    flag ? `${w("heldAt")} = now()` : "",
    kind ? `${w("holdKind")} = hold_task.kind` : "",
    ctx.has("items", "holdReturnStage") && co.holdStage !== null
      ? `${w("holdReturnStage")} = x.${w("stage")}`
      : "",
    co.holdStage === null ? "" : `${w("stage")} = v_stage`,
  ].filter((set) => set !== "");

  const clear = [
    flag ? `${w("heldAt")} = null` : "",
    kind ? `${w("holdKind")} = null` : "",
    ctx.has("items", "holdReturnStage") ? `${w("holdReturnStage")} = null` : "",
    co.holdStage !== null && ctx.has("items", "holdReturnStage")
      ? `${w("stage")} = coalesce(x.${w("holdReturnStage")}, x.${w("stage")})`
      : "",
  ].filter((set) => set !== "");

  const claimDrop = ctx.hasTable("claims")
    ? `\n  delete from ${t("claims")} c where c.${k("task")} = v_row.${w("id")};`
    : "";

  return `
-- Puts a task on hold: kind says what it waits for (a short lowercase word),
-- note reaches ask_user_ids through the task's conversation with mentions.
-- A live claim is dropped. Each asked user needs tasks.read.
create or replace function ${fn("hold_task")}(task uuid, kind text, note text default null, ask_user_ids uuid[] default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("items")};
  v_stage uuid;
  v_note text := nullif(trim(hold_task.note), '');
  v_ask uuid[] := array(select distinct x from unnest(coalesce(hold_task.ask_user_ids, '{}')) x where x is not null);
  v_conversation text;${approval === null ? "" : "\n  v_request jsonb;"}
begin
  if hold_task.kind is null or hold_task.kind !~ '^[a-z][a-z_]{0,31}$' then
    ${fail("TASK_HOLD_INVALID", "kind must be a short lowercase word such as review or input", "22023")}
  end if;${
    co.holdKinds === null
      ? ""
      : `
  if hold_task.kind <> all(array[${co.holdKinds.map((each) => sqlString(each)).join(", ")}]) then
    ${fail("TASK_HOLD_INVALID", `kind must be one of ${co.holdKinds.join(", ")}`, "22023")}
  end if;`
  }
  ${load(ctx, n, "hold_task", n.write)}
  if v_row.${w("closedAt")} is not null then
    ${fail("TASK_CLOSED", "a closed task can't be held", "55000")}
  end if;${
    flag
      ? `
  if v_row.${w("heldAt")} is not null then
    ${fail("TASK_HELD", "the task is already on hold", "55000")}
  end if;`
      : ""
  }
  if exists (select 1 from unnest(v_ask) x where not ${ctx.scope.canUser("x", `v_row.${w("tenant")}`, n.read)}) then
    ${fail("TASK_HOLD_INVALID", "an asked user can't read tasks in this organization", "22023")}
  end if;${moveIn}${claimDrop}
  update ${t("items")} x set ${sets.join(", ")} where x.${w("id")} = v_row.${w("id")};${open}${messaging}
  select * into v_row from ${t("items")} x where x.${w("id")} = v_row.${w("id")};
  ${taskRecord(ctx, n, "task.held", "v_row", `, 'kind', hold_task.kind, 'note', v_note, 'askUserIds', to_jsonb(v_ask)${approval === null ? "" : ", 'approvalId', v_request ->> 'id'"}`)}
  return (select ${h.row("x")} from ${t("items")} x where x.${w("id")} = v_row.${w("id")});
end;
$$;
${userGrant(`${fn("hold_task")}(uuid, text, text, uuid[])`)}

-- Ends a hold. With the hold stage option the task returns to the stage it
-- left. A pending approval request of the hold is cancelled, and
-- task.hold_released says so with approvalCancelled.
create or replace function ${fn("release_task_hold")}(task uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("items")};
  v_kind text;${approval === null ? "" : "\n  v_cancelled boolean := false;"}
begin
  ${load(ctx, n, "release_task_hold", n.write)}${
    flag
      ? `
  if v_row.${w("heldAt")} is null then
    ${fail("TASK_NOT_HELD", "the task isn't on hold", "55000")}
  end if;`
      : ""
  }
  v_kind := ${kind ? `v_row.${w("holdKind")}` : "null"};
  update ${t("items")} x set ${clear.join(", ")} where x.${w("id")} = v_row.${w("id")} returning * into v_row;${
    approval === null
      ? ""
      : `
  ${cancelHoldRequestSql(ctx, n, `v_row.${w("id")}`)}
  v_cancelled := found;`
  }
  ${taskRecord(ctx, n, "task.hold_released", "v_row", `, 'kind', v_kind, 'returnStageId', v_row.${w("stage")}${approval === null ? "" : ", 'approvalCancelled', v_cancelled"}`)}
  return (select ${h.row("x")} from ${t("items")} x where x.${w("id")} = v_row.${w("id")});
end;
$$;
${userGrant(`${fn("release_task_hold")}(uuid)`)}
`;
}

/** Outcomes: complete, cancel, fail and reopen with a note. */
export function outcomesSql(
  ctx: BlockSqlContext,
  n: TaskNames,
  h: { readonly row: (alias: string) => string },
): string {
  const { fn, t } = n;
  const w = (column: string): string => n.c("items", column);

  // An app whose state values have no canceled entry has no failure to record.
  const noCanceled =
    ctx.mapsValues("items", "state") &&
    ctx.appValues("items", "state", "canceled").length === 0;

  const failed = ctx.has("items", "closeReason")
    ? `
      begin
        update ${t("items")} x set ${w("stage")} = v_stage, ${w("closeReason")} = ${ctx.cast("items", "closeReason", "'failed'")} where x.${w("id")} = v_row.${w("id")};
      exception when check_violation or invalid_text_representation then
        update ${t("items")} x set ${w("stage")} = v_stage where x.${w("id")} = v_row.${w("id")};
      end;`
    : `
      update ${t("items")} x set ${w("stage")} = v_stage where x.${w("id")} = v_row.${w("id")};`;

  return `
-- Closes or reopens a task with a note. outcome is completed, canceled, failed
-- or open. stage defaults to the first stage of the matching category in the
-- task's pipeline. failed lands in the canceled category with close reason
-- failed (not_planned where the column can't hold it). The note rides on
-- task.closed, and failed also records task.failed.
create or replace function ${fn("close_task")}(task uuid, outcome text, note text default null, stage uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("items")};
  v_stage uuid;
  v_note text := nullif(trim(close_task.note), '');
begin
  if close_task.outcome is null or close_task.outcome not in ('completed', 'canceled', 'failed', 'open') then
    ${fail("TASK_OUTCOME_INVALID", "outcome is completed, canceled, failed or open", "22023")}
  end if;${
    noCanceled
      ? `
  if close_task.outcome in ('canceled', 'failed') then
    ${fail("TASK_OUTCOME_UNAVAILABLE", "this tasks table has no canceled state", "22023")}
  end if;`
      : ""
  }
  ${load(ctx, n, "close_task", n.write)}
  if close_task.outcome = 'open' and v_row.${w("closedAt")} is null then
    return (select ${h.row("x")} from ${t("items")} x where x.${w("id")} = v_row.${w("id")});
  end if;
  if close_task.outcome <> 'open' and v_row.${w("closedAt")} is not null then
    ${fail("TASK_CLOSED", "the task is already closed", "55000")}
  end if;
  ${ctx.hook("before_task_close", [
    ["uuid", `v_row.${w("id")}`],
    ["text", "close_task.outcome"],
    ["text", "v_note"],
  ])}
  v_stage := coalesce(close_task.stage, case close_task.outcome
    when 'completed' then ${stageByCategory(ctx, `v_row.${w("pipeline")}`, "completed")}
    when 'open' then ${stageByCategory(ctx, `v_row.${w("pipeline")}`, "unstarted")}
    else ${stageByCategory(ctx, `v_row.${w("pipeline")}`, "canceled")} end);
  if v_stage is null then
    ${fail("TASK_STAGE_REQUIRED", "the task's pipeline has no stage for this outcome; pass a stage", "22023")}
  end if;
  perform set_config('bsb.close_note', coalesce(v_note, ''), true);
  perform set_config('bsb.close_by', coalesce(auth.uid()::text, ''), true);
  begin
    if close_task.outcome = 'failed' then${failed}
    else
      update ${t("items")} x set ${w("stage")} = v_stage where x.${w("id")} = v_row.${w("id")};
    end if;
  exception when check_violation or foreign_key_violation then
    ${fail("TASK_ATTRS_INVALID", "the stage can't be used for this task", "22023")}
  end;
  perform set_config('bsb.close_note', '', true);
  select * into v_row from ${t("items")} x where x.${w("id")} = v_row.${w("id")};
  if close_task.outcome = 'failed' then
    ${taskRecord(ctx, n, "task.failed", "v_row", ", 'note', v_note")}
  end if;
  return (select ${h.row("x")} from ${t("items")} x where x.${w("id")} = v_row.${w("id")});
end;
$$;
${userGrant(`${fn("close_task")}(uuid, text, text, uuid)`)}
`;
}
