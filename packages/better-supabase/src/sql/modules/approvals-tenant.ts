import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  ExtraColumn,
} from "../context.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  activeMembership,
  addExtraColumns,
  extraFieldsArg,
  extraFieldsJson,
  fail,
  insertExtraColumns,
  pageSize,
  SERVICE_CALLER,
  updateExtraColumns,
  userGrant,
  writeExtraColumns,
} from "../shared.ts";
import {
  approvalConditions,
  approvalConditionSql,
} from "./approvals-conditions.ts";
import { approvalPolicies, floorsJson } from "./approvals-policies.ts";
import { lockModuleTable } from "./over-app.ts";

/** The table `options.tenantPolicies` adds, for the module's names. */
export const TENANT_POLICY_TABLES = {
  policies: {
    name: "approval_policies",
    app: {},
    lifecycle: { tenant: "tenant", user: "createdBy", export: true },
    optional: ["conditions", "expiresIn", "createdBy", "updatedAt", "effect"],
    typed: ["mode"],
    columns: {
      id: "id",
      tenant: "tenant_id",
      subjectType: "subject_type",
      action: "action",
      name: "name",
      conditions: "conditions",
      mode: "mode",
      steps: "steps",
      selfApproval: "self_approval",
      expiresIn: "expires_in",
      enabled: "enabled",
      createdBy: "created_by",
      createdAt: "created_at",
      updatedAt: "updated_at",
      effect: "effect",
    },
  },
} as const;

/** The keys the policy reads return next to the extra columns. */
const POLICY_KEYS: readonly string[] = ["fields"];

/** `blocks.approvals.options.policyExtraColumns`, on the tenant policies table. */
const policyExtras = (ctx: BlockSqlContext): readonly ExtraColumn[] =>
  tenantPoliciesOn(ctx)
    ? ctx.extraColumns("policies", POLICY_KEYS, "policyExtraColumns")
    : [];

/** Whether `blocks.approvals.options.tenantPolicies` is on. */
export const tenantPoliciesOn = (ctx: BlockSqlContext): boolean =>
  ctx.flag("tenantPolicies", false);

/**
 * Whether `blocks.approvals.options.platformPolicies` is on: rows of the tenant
 * policies table without a tenant are platform policies, edited at runtime by
 * platform staff, that apply to every organization and can stand in for a
 * config floor.
 */
export function platformPoliciesOn(ctx: BlockSqlContext): boolean {
  const on = ctx.flag("platformPolicies", false);

  if (on && !tenantPoliciesOn(ctx)) {
    throw new TypeError(
      "blocks.approvals.options.platformPolicies needs blocks.approvals.options.tenantPolicies",
    );
  }

  return on;
}

/**
 * `blocks.approvals.options.tenantless`: the subject types whose requests may
 * have no organization, for personal or platform actions.
 */
export const tenantlessTypes = (ctx: BlockSqlContext): readonly string[] =>
  ctx.list("tenantless", []);

/** SQL that is true when `type` may be filed without an organization. */
function tenantlessType(ctx: BlockSqlContext, type: string): string {
  const types = tenantlessTypes(ctx);

  return types.length === 0
    ? "false"
    : `${type} in (${types.map(sqlString).join(", ")})`;
}

/** The employees module when it renders tables the approvals SQL can read. */
const employeesOf = (
  ctx: BlockSqlContext,
): ReturnType<BlockSqlContext["of"]> | undefined =>
  ctx.installed("employees") && ctx.of("employees").mode !== "custom"
    ? ctx.of("employees")
    : undefined;

/**
 * The user id of the requester's manager in the request's tenant, as a SQL
 * expression, or `undefined` without the employees module. `employee`, a text
 * SQL expression, names the employee whose manager it is instead when it is not
 * null. An offboarded manager decides nothing.
 */
export function managerOf(
  ctx: BlockSqlContext,
  requester: string,
  tenant: string,
  employee?: string,
): string | undefined {
  const employees = employeesOf(ctx);

  if (employees === undefined) {
    return undefined;
  }

  const e = (column: string): string => employees.col("employees", column);
  const table = employees.table("employees");

  const who =
    employee === undefined
      ? `me.${e("user")} = ${requester}`
      : `(case when ${employee} is not null then me.${e("id")}::text = ${employee} else me.${e("user")} = ${requester} end)`;

  return `(select mgr.${e("user")} from ${table} me
      join ${table} mgr on mgr.${e("id")} = me.${e("manager")}
      where me.${e("tenant")} = ${tenant} and ${who}
        and mgr.${e("user")} is not null and ${employees.is("employees", "status", `mgr.${e("status")}`, ["offboarded"], true)}
      limit 1)`;
}

/** Whether `user` is the requester's manager and still a member. */
export function managerMatch(
  ctx: BlockSqlContext,
  args: {
    readonly requester: string;
    readonly tenant: string;
    readonly user: string;
    /** The employee whose manager decides, as text, when not null. */
    readonly employee?: string;
  },
): string {
  const manager = managerOf(ctx, args.requester, args.tenant, args.employee);

  if (manager === undefined) {
    return "false";
  }

  const members = ctx.of("memberships");
  const m = (column: string): string => members.col("memberships", column);

  return `(coalesce(${manager} = ${args.user}, false) and exists (
      select 1 from ${members.table("memberships")} mm
      where mm.${m("tenant")} = ${args.tenant} and mm.${m("user")} = ${args.user}${activeMembership(ctx, "mm")}
    ))`;
}

/** What the request functions share with the rest of the module. */
export interface ApprovalRequestHelpers {
  readonly json: (row: string) => string;
  readonly record: (event: string, row: string, audit: boolean) => string;
  readonly notFound: string;
  /** Whether the caller may write the subject, for request_approval. */
  readonly subjectWrite: string;
  readonly permissions: {
    readonly read: string;
    readonly request: string;
    readonly manage: string;
  };
  readonly extras: readonly ExtraColumn[];
}

/** Request_approval's leading argument types, before `fields`. */
const requestArgs = (ctx: BlockSqlContext): string =>
  `${ctx.idType}, text, text, text, text, jsonb`;

/**
 * Whether policy snapshot `p` asks for anything: a `confirm` mode, or steps an
 * approver decides.
 */
const required = (p: string): string =>
  `(coalesce(${p} ->> 'mode', 'authorize') = 'confirm' or jsonb_array_length(coalesce(${p} -> 'steps', '[]'::jsonb)) > 0)`;

/** How strict a mode with its steps is: 0 asks nothing, 2 needs an approver. */
const level = (mode: string, steps: string): string =>
  `case when ${mode} = 'authorize' and jsonb_array_length(${steps}) > 0 then 2 when ${mode} = 'confirm' then 1 else 0 end`;

function effectivePolicySql(ctx: BlockSqlContext): string {
  const fn = (name: string): string => ctx.fn(name);
  const signature = `${fn("approval_effective_policy")}(${ctx.idType}, text, text, jsonb)`;

  if (!tenantPoliciesOn(ctx)) {
    return `
-- The policy a request snapshots: options.policies, as tenant policies are off.
create or replace function ${fn("approval_effective_policy")}(tenant ${ctx.idType}, subject_type text, action text, subject jsonb default '{}'::jsonb)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select ${fn("approval_policy")}(approval_effective_policy.subject_type, approval_effective_policy.action)
$$;
revoke execute on function ${signature} from public, anon, authenticated;`;
  }

  const p = (column: string): string => ctx.col("policies", column);
  const has = (column: string): boolean => ctx.has("policies", column);
  const platform = platformPoliciesOn(ctx);
  const payload = approvalConditions(ctx) === "payload";

  const rules =
    !payload && ctx.installed("automations")
      ? ctx.of("automations")
      : undefined;

  const conditions = has("conditions")
    ? payload
      ? `
    if v_row.${p("conditions")} is not null
      and not ${fn("approval_condition")}(v_row.${p("conditions")}, coalesce(approval_effective_policy.subject, '{}'::jsonb)) then
      continue;
    end if;`
      : rules === undefined
        ? `
    if v_row.${p("conditions")} is not null then
      continue;
    end if;`
        : `
    if v_row.${p("conditions")} is not null then
      if v_fields is null then
        v_fields := ${rules.fn("rule_field_map")}(approval_effective_policy.subject_type);
      end if;
      if not ${rules.fn("rule_matches")}(v_row.${p("conditions")}, coalesce(approval_effective_policy.subject, '{}'::jsonb), v_fields, 'UTC', now()) then
        continue;
      end if;
    end if;`
    : "";

  const missingFloor = platform
    ? `
    v_floor := '{"steps": [], "selfApproval": true, "expiresIn": null, "run": null}'::jsonb;
    v_matched := false;`
    : `
    return null;`;

  return `
-- The policy a request snapshots: the options.policies floor, tightened by
-- every enabled tenant policy whose conditions match the request payload.
-- A policy matches its subject type and action, \`*\` for any, and the
-- floor's effects when it names one. Steps add up, the stricter mode wins,
-- self-approval needs every policy to allow it and the shortest expiry
-- applies.${platform ? "\n-- Platform policies (no tenant) come first and stand in for a missing floor." : ""}
create or replace function ${fn("approval_effective_policy")}(tenant ${ctx.idType}, subject_type text, action text, subject jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_floor jsonb := ${fn("approval_policy")}(approval_effective_policy.subject_type, approval_effective_policy.action);
  v_row ${ctx.table("policies")}%rowtype;
  v_steps jsonb;
  v_level integer;
  v_self boolean;
  v_expires interval;
  v_ids jsonb := '[]'::jsonb;
  v_fields jsonb;
  v_effects jsonb;
  v_matched boolean := true;
begin
  if v_floor is null then${missingFloor}
  end if;
  v_effects := coalesce(v_floor -> 'effects', '[]'::jsonb);
  v_steps := coalesce(v_floor -> 'steps', '[]'::jsonb);
  v_level := ${level("coalesce(v_floor ->> 'mode', 'authorize')", "v_steps")};
  v_self := coalesce((v_floor ->> 'selfApproval')::boolean, false);
  v_expires := (v_floor ->> 'expiresIn')::interval;
  for v_row in
    select * from ${ctx.table("policies")} x
    where (x.${p("tenant")} = approval_effective_policy.tenant${platform ? ` or x.${p("tenant")} is null` : ""})
      and (x.${p("subjectType")} = approval_effective_policy.subject_type or x.${p("subjectType")} = '*')
      and (x.${p("action")} = approval_effective_policy.action or x.${p("action")} = '*')${
        has("effect")
          ? `
      and (x.${p("effect")} is null or v_effects ? x.${p("effect")})`
          : ""
      }
      and x.${p("enabled")}
    order by ${platform ? `x.${p("tenant")} is null desc, ` : ""}x.${p("createdAt")}, x.${p("id")}
  loop${
    platform
      ? `
    if not v_matched and v_row.${p("tenant")} is not null then
      continue;
    end if;`
      : ""
  }${conditions}
    v_matched := true;
    v_steps := v_steps || v_row.${p("steps")};
    v_level := greatest(v_level, ${level(`v_row.${p("mode")}::text`, `v_row.${p("steps")}`)});
    v_self := v_self and v_row.${p("selfApproval")};${
      has("expiresIn")
        ? `
    v_expires := least(v_expires, v_row.${p("expiresIn")});`
        : ""
    }
    v_ids := v_ids || to_jsonb(v_row.${p("id")});
  end loop;
  if not v_matched then
    return null;
  end if;
  return jsonb_build_object(
    'steps', v_steps, 'selfApproval', v_self, 'expiresIn', v_expires::text, 'run', v_floor -> 'run',
    'mode', case when v_level = 1 then 'confirm' else 'authorize' end, 'policies', v_ids
  ) || case when jsonb_array_length(v_effects) > 0 then jsonb_build_object('effects', v_effects) else '{}'::jsonb end;
end;
$$;
revoke execute on function ${signature} from public, anon, authenticated;${payload ? approvalConditionSql(ctx) : ""}`;
}

/**
 * `steps` with `required: "all"` on a step that only lists users replaced by
 * their count, as the config parser does.
 */
const allUsersCounted = (
  steps: string,
): string => `(select coalesce(jsonb_agg(case when s -> 'required' = '"all"'::jsonb and (s -> 'approvers') ? 'users'
    then jsonb_set(s, '{required}', to_jsonb(jsonb_array_length(s -> 'approvers' -> 'users'))) else s end order by o), '[]'::jsonb)
    from jsonb_array_elements(${steps}) with ordinality e(s, o))`;

/**
 * PL/pgSQL that raises `invalid` unless every step of `steps` (a jsonb array
 * expression) names approvers and a valid required count and escalation. It
 * reads and writes `v_step` and `v_who`.
 */
const stepsCheck = (
  steps: string,
  invalid: string,
  manager: boolean,
): string => `  for v_step in select * from jsonb_array_elements(${steps}) loop
    if jsonb_typeof(v_step) <> 'object' then
      ${invalid}
    end if;
    for v_who in select a.w from (values (v_step -> 'approvers', true), (v_step -> 'escalateTo', v_step ? 'escalateTo')) a(w, checked) where a.checked loop
      if jsonb_typeof(v_who) is distinct from 'object'
        or not (v_who ?| array['permission', 'role', 'team', 'users', 'manager'])
        or (v_who ? 'manager' and ${manager ? "v_who -> 'manager' <> 'true'::jsonb" : "true"})
        or (v_who ? 'users' and (jsonb_typeof(v_who -> 'users') <> 'array'
          or exists (select 1 from jsonb_array_elements(v_who -> 'users') u
            where jsonb_typeof(u) <> 'string' or u #>> '{}' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'))) then
        ${invalid}
      end if;
    end loop;
    if (v_step ? 'required' and v_step -> 'required' <> '"all"'::jsonb and (jsonb_typeof(v_step -> 'required') <> 'number' or (v_step ->> 'required')::numeric < 1
        or (v_step ->> 'required')::numeric <> trunc((v_step ->> 'required')::numeric)))
      or (v_step -> 'required' = '"all"'::jsonb and (v_step -> 'approvers') - 'permission' <> '{}'::jsonb
        and ((v_step -> 'approvers') - 'users' <> '{}'::jsonb or jsonb_array_length(v_step -> 'approvers' -> 'users') = 0))
      or (jsonb_typeof(v_step -> 'required') = 'number' and (v_step -> 'approvers') - 'users' = '{}'::jsonb
        and (v_step ->> 'required')::numeric > jsonb_array_length(v_step -> 'approvers' -> 'users'))
      or ((v_step ? 'escalateAfter') <> (v_step ? 'escalateTo'))
      or (v_step ? 'escalateAfter' and (jsonb_typeof(v_step -> 'escalateAfter') <> 'string' or (v_step ->> 'escalateAfter')::interval <= interval '0')) then
      ${invalid}
    end if;
  end loop;`;

function tenantPoliciesSql(
  ctx: BlockSqlContext,
  helpers: ApprovalRequestHelpers,
): string {
  const fn = (name: string): string => ctx.fn(name);
  const t = ctx.table("policies");
  const p = (column: string): string => ctx.col("policies", column);
  const has = (column: string): boolean => ctx.has("policies", column);

  const or = (row: string, column: string): string =>
    has(column) ? `${row}.${p(column)}` : "null";

  const { manage, read } = helpers.permissions;
  const platform = platformPoliciesOn(ctx);
  const platformKey = ctx.config.permissions["platform"];

  const platformManage =
    platformKey === undefined ? manage : sqlString(platformKey);

  const platformRead =
    platformKey === undefined ? read : sqlString(platformKey);

  const payload = approvalConditions(ctx) === "payload";

  const rules =
    !payload && ctx.installed("automations")
      ? ctx.of("automations")
      : undefined;

  const manager = employeesOf(ctx) !== undefined;
  const extras = policyExtras(ctx);

  const inserted = insertExtraColumns(
    t,
    extras,
    "coalesce(save_approval_policy.policy -> 'fields', '{}'::jsonb)",
  );

  // Who may change the policies of tenant `tenant`; platform staff for the
  // platform policies (no tenant).
  const manages = (tenant: string): string =>
    platform
      ? `(case when ${tenant} is null then ${ctx.staff(platformManage)} else (${SERVICE_CALLER} or ${ctx.can("tenant", tenant, manage)}) end)`
      : `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, manage)})`;

  const json = (row: string): string =>
    `jsonb_build_object('id', ${row}.${p("id")}, 'organizationId', ${row}.${p("tenant")}, 'subjectType', ${row}.${p("subjectType")}, 'action', ${row}.${p("action")}, 'effect', ${or(row, "effect")}, 'name', ${row}.${p("name")}, 'conditions', ${or(row, "conditions")}, 'mode', ${row}.${p("mode")}, 'steps', ${row}.${p("steps")}, 'selfApproval', ${row}.${p("selfApproval")}, 'expiresIn', ${or(row, "expiresIn")}::text, 'enabled', ${row}.${p("enabled")}, 'createdAt', ${row}.${p("createdAt")}, 'updatedAt', ${or(row, "updatedAt")}${extraFieldsJson(row, extras)})`;

  const column = (
    logical: string,
    definition: (name: string) => string,
  ): string => (has(logical) ? `\n  ${definition(p(logical))},` : "");

  const table = ctx.manages
    ? `
create table if not exists ${t} (
  ${p("id")} uuid primary key default gen_random_uuid(),
  ${p("tenant")} ${ctx.idType}${platform ? "" : " not null"},
  ${p("subjectType")} text not null,
  ${p("action")} text not null,
  ${p("name")} text not null check (length(${p("name")}) between 1 and 200),${column("conditions", (name) => `${name} jsonb`)}${column("effect", (name) => `${name} text`)}
  ${p("mode")} text not null default 'authorize' check (${p("mode")} in ('confirm', 'authorize')),
  ${p("steps")} jsonb not null default '[]'::jsonb check (jsonb_typeof(${p("steps")}) = 'array'),
  ${p("selfApproval")} boolean not null default false,${column("expiresIn", (name) => `${name} interval check (${name} is null or ${name} > interval '0')`)}
  ${p("enabled")} boolean not null default true,${column("createdBy", (name) => `${name} uuid`)}
  ${p("createdAt")} timestamptz not null default now()${has("updatedAt") ? `,\n  ${p("updatedAt")} timestamptz not null default now()` : ""}
);
${has("effect") ? `alter table ${t} add column if not exists ${p("effect")} text;\n` : ""}${platform ? `alter table ${t} alter column ${p("tenant")} drop not null;\n` : ""}create index if not exists ${sqlIdent(`${ctx.tableName("policies").name}_lookup_idx`)} on ${t} (${p("tenant")}, ${p("subjectType")}, ${p("action")});${addExtraColumns(t, extras)}
${lockModuleTable(ctx, "policies", { read: true })}
${renderPolicy(makePolicy({ table: t, name: ctx.naming.rename("approval_policies_read"), command: "select", roles: ["authenticated"], using: ctx.scope.check(p("tenant"), read) }), { drop: true, target: t })}`
    : "";

  const conditionCheck = has("conditions")
    ? payload
      ? `
  if v_conditions is not null then
    perform ${fn("approval_condition")}(v_conditions, '{}'::jsonb);
  end if;`
      : rules
        ? `
  if v_conditions is not null then
    v_fields := ${rules.fn("rule_field_map")}(v_type);
    if v_fields = '{}'::jsonb then
      ${fail("APPROVAL_FIELDS_MISSING", "no rule fields for this subject type; sync them first", "22023")}
    end if;
    perform ${rules.fn("rule_check")}(v_conditions, v_fields, 1);
  end if;`
        : `
  if v_conditions is not null then
    ${fail("APPROVAL_CONDITIONS_UNSUPPORTED", 'approval policy conditions need the automations module, or options.conditions: "payload"', "22023")}
  end if;`
    : `
  if v_conditions is not null then
    ${fail("APPROVAL_CONDITIONS_UNSUPPORTED", "this approval policies table has no conditions column", "22023")}
  end if;`;

  const floorPolicies = approvalPolicies(ctx);
  const floors = floorsJson(floorPolicies);

  const floorType = floorPolicies.some((each) => each.subjectType === "*")
    ? "f.value ->> 'subjectType' in (v_type, '*')"
    : "f.value ->> 'subjectType' = v_type";

  // A tenant policy tightens a config floor (or, with platform policies, an
  // enabled platform policy) for its subject type, action and effect; `*`
  // matches any.
  const floorExists = `(exists (
      select 1 from jsonb_array_elements(${floors}) f
      where (v_type = '*' or ${floorType})
        and (v_action = '*' or f.value ->> 'action' in (v_action, '*'))
        and (v_effect is null or f.value -> 'effects' ? v_effect)
    )${
      platform
        ? ` or (save_approval_policy.tenant is null) or exists (
      select 1 from ${t} f
      where f.${p("tenant")} is null and f.${p("enabled")}
        and (f.${p("subjectType")} in (v_type, '*'))
        and (f.${p("action")} in (v_action, '*'))${has("effect") ? `\n        and (f.${p("effect")} is null or f.${p("effect")} = v_effect)` : ""}
    )`
        : ""
    })`;

  const stepsInvalid = fail(
    "APPROVAL_POLICY_INVALID",
    `steps must be a list of { approvers: { permission, role, team, users${manager ? ", manager" : ""} }, required, escalateAfter, escalateTo } objects`,
    "22023",
  );

  return `${table}

-- Creates or changes a tenant policy. policy is { id?, subjectType, action,
-- name, conditions, mode, steps, selfApproval, expiresIn, enabled }; keys
-- left out keep their value. A tenant policy only adds to the options.policies
-- floor for its subject type and action, so it can never loosen it.
create or replace function ${fn("save_approval_policy")}(tenant ${ctx.idType}, policy jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_old ${t}%rowtype;
  v_row ${t}%rowtype;
  v_type text;
  v_action text;
  v_conditions jsonb;
  v_steps jsonb;
  v_step jsonb;
  v_fields jsonb;
  v_effect text;
  v_who jsonb;
begin
  if not ${manages("save_approval_policy.tenant")} then
    ${fail("APPROVAL_FORBIDDEN", "managing approval policies needs approvals.manage")}
  end if;
  if jsonb_typeof(save_approval_policy.policy) is distinct from 'object' then
    ${fail("APPROVAL_POLICY_INVALID", "policy must be an object", "22023")}
  end if;
  if save_approval_policy.policy ? 'id' then
    select * into v_old from ${t} x
    where x.${p("id")} = (save_approval_policy.policy ->> 'id')::uuid and x.${p("tenant")} is not distinct from save_approval_policy.tenant
    for update;
    if not found then
      ${fail("APPROVAL_POLICY_NOT_FOUND", "approval policy not found", "P0002")}
    end if;
  end if;
  v_type := coalesce(save_approval_policy.policy ->> 'subjectType', v_old.${p("subjectType")});
  v_action := coalesce(save_approval_policy.policy ->> 'action', v_old.${p("action")});
  v_effect := ${has("effect") ? `case when save_approval_policy.policy ? 'effect' then nullif(save_approval_policy.policy ->> 'effect', '') else v_old.${p("effect")} end` : "null"};${
    has("effect")
      ? ""
      : `
  if nullif(save_approval_policy.policy ->> 'effect', '') is not null then
    ${fail("APPROVAL_EFFECT_UNSUPPORTED", "this approval policies table has no effect column", "22023")}
  end if;`
  }
  if v_type is null or v_action is null or not ${floorExists} then
    ${fail("APPROVAL_POLICY_UNKNOWN", "a tenant policy tightens an options.policies entry, and there is none for this subject type, action and effect", "22023")}
  end if;
  v_conditions := case when save_approval_policy.policy ? 'conditions' then nullif(save_approval_policy.policy -> 'conditions', 'null'::jsonb) else ${or("v_old", "conditions")} end;${conditionCheck}
  v_steps := coalesce(save_approval_policy.policy -> 'steps', v_old.${p("steps")}, '[]'::jsonb);
  if jsonb_typeof(v_steps) <> 'array' or jsonb_array_length(v_steps) > 20 then
    ${stepsInvalid}
  end if;
${stepsCheck("v_steps", stepsInvalid, manager)}
  v_steps := ${allUsersCounted("v_steps")};
  if coalesce(save_approval_policy.policy ->> 'mode', v_old.${p("mode")}::text, 'authorize') not in ('confirm', 'authorize') then
    ${fail("APPROVAL_POLICY_INVALID", "mode must be confirm or authorize", "22023")}
  end if;
  if v_old.${p("id")} is null then
    insert into ${t} (${p("tenant")}, ${p("subjectType")}, ${p("action")}, ${p("name")}${has("conditions") ? `, ${p("conditions")}` : ""}${has("effect") ? `, ${p("effect")}` : ""}, ${p("mode")}, ${p("steps")}, ${p("selfApproval")}${has("expiresIn") ? `, ${p("expiresIn")}` : ""}, ${p("enabled")}${has("createdBy") ? `, ${p("createdBy")}` : ""}${inserted.columns})
    values (save_approval_policy.tenant, v_type, v_action, btrim(save_approval_policy.policy ->> 'name')${has("conditions") ? ", v_conditions" : ""}${has("effect") ? ", v_effect" : ""},
      ${ctx.cast("policies", "mode", "coalesce(save_approval_policy.policy ->> 'mode', 'authorize')")}, v_steps,
      coalesce((save_approval_policy.policy ->> 'selfApproval')::boolean, false)${has("expiresIn") ? ", (save_approval_policy.policy ->> 'expiresIn')::interval" : ""},
      coalesce((save_approval_policy.policy ->> 'enabled')::boolean, true)${has("createdBy") ? ", auth.uid()" : ""}${inserted.values})
    returning * into v_row;
  else
    update ${t} x set
      ${p("subjectType")} = v_type,
      ${p("action")} = v_action,
      ${p("name")} = coalesce(btrim(save_approval_policy.policy ->> 'name'), x.${p("name")}),${has("conditions") ? `\n      ${p("conditions")} = v_conditions,` : ""}${has("effect") ? `\n      ${p("effect")} = v_effect,` : ""}
      ${p("mode")} = coalesce(${ctx.cast("policies", "mode", "save_approval_policy.policy ->> 'mode'")}, x.${p("mode")}),
      ${p("steps")} = v_steps,
      ${p("selfApproval")} = coalesce((save_approval_policy.policy ->> 'selfApproval')::boolean, x.${p("selfApproval")}),${has("expiresIn") ? `\n      ${p("expiresIn")} = case when save_approval_policy.policy ? 'expiresIn' then (save_approval_policy.policy ->> 'expiresIn')::interval else x.${p("expiresIn")} end,` : ""}
      ${p("enabled")} = coalesce((save_approval_policy.policy ->> 'enabled')::boolean, x.${p("enabled")})${has("updatedAt") ? `,\n      ${p("updatedAt")} = now()` : ""}${updateExtraColumns(t, extras, "(save_approval_policy.policy -> 'fields')")}
    where x.${p("id")} = v_old.${p("id")}
    returning * into v_row;
  end if;
  ${ctx.record({
    type: "approval_policy.saved",
    payload: `jsonb_build_object('organizationId', v_row.${p("tenant")}::text, 'id', v_row.${p("id")}, 'subjectType', v_row.${p("subjectType")}, 'action', v_row.${p("action")})`,
    subject: `'approval-policies/' || v_row.${p("id")}::text`,
    tenant: `v_row.${p("tenant")}`,
    audit: {
      category: "configuration",
      targetType: "approval_policy",
      recordId: `v_row.${p("id")}::text`,
      summary: `'saved approval policy ' || v_row.${p("name")}`,
    },
  })}
  return ${json("v_row")};
exception
  when invalid_text_representation or invalid_datetime_format or not_null_violation or check_violation then
    ${fail("APPROVAL_POLICY_INVALID", "policy has an invalid name, mode, expiry or flag", "22023")}
end;
$$;
${userGrant(`${fn("save_approval_policy")}(${ctx.idType}, jsonb)`)}

create or replace function ${fn("remove_approval_policy")}(policy_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t}%rowtype;
begin
  select * into v_row from ${t} x where x.${p("id")} = remove_approval_policy.policy_id;
  if not found then
    return false;
  end if;
  if not ${manages(`v_row.${p("tenant")}`)} then
    ${fail("APPROVAL_FORBIDDEN", "managing approval policies needs approvals.manage")}
  end if;
  delete from ${t} x where x.${p("id")} = v_row.${p("id")};
  ${ctx.record({
    type: "approval_policy.removed",
    payload: `jsonb_build_object('organizationId', v_row.${p("tenant")}::text, 'id', v_row.${p("id")}, 'subjectType', v_row.${p("subjectType")}, 'action', v_row.${p("action")})`,
    subject: `'approval-policies/' || v_row.${p("id")}::text`,
    tenant: `v_row.${p("tenant")}`,
    audit: {
      category: "configuration",
      targetType: "approval_policy",
      recordId: `v_row.${p("id")}::text`,
      summary: `'removed approval policy ' || v_row.${p("name")}`,
    },
  })}
  return true;
end;
$$;
${userGrant(`${fn("remove_approval_policy")}(uuid)`)}

create or replace function ${fn("list_approval_policies")}(tenant ${ctx.idType}, subject_type text default null, page_size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${
    platform
      ? `(case when list_approval_policies.tenant is null then ${ctx.staff(platformRead)} else (${SERVICE_CALLER} or ${ctx.can("tenant", "list_approval_policies.tenant", read)}) end)`
      : `(${SERVICE_CALLER} or ${ctx.can("tenant", "list_approval_policies.tenant", read)})`
  } then
    ${fail("APPROVAL_FORBIDDEN", "reading approval policies needs approvals.read")}
  end if;
  return coalesce((
    select jsonb_agg(${json("x")} order by x.${p("subjectType")}, x.${p("action")}, x.${p("createdAt")}, x.${p("id")})
    from (
      select * from ${t} y
      where (y.${p("tenant")} = list_approval_policies.tenant or (list_approval_policies.tenant is null and y.${p("tenant")} is null))
        and (list_approval_policies.subject_type is null or y.${p("subjectType")} = list_approval_policies.subject_type)
      order by y.${p("subjectType")}, y.${p("action")}, y.${p("createdAt")}, y.${p("id")}
      limit ${pageSize("list_approval_policies.page_size", 100, 500)}
    ) x
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_approval_policies")}(${ctx.idType}, text, integer)`)}`;
}

function requestSql(
  ctx: BlockSqlContext,
  helpers: ApprovalRequestHelpers,
): string {
  const fn = (name: string): string => ctx.fn(name);
  const requests = ctx.table("requests");
  const c = (column: string): string => ctx.col("requests", column);
  const fingerprinted = ctx.has("requests", "fingerprint");
  const { extras, json, subjectWrite } = helpers;
  const { request } = helpers.permissions;
  const args = requestArgs(ctx);
  const fields = extraFieldsArg(extras);

  const otherNew =
    extras.length === 0 ? `${args}, jsonb, text` : `${args}, text`;

  const manager = employeesOf(ctx) !== undefined;

  const ownInvalid = fail(
    "APPROVAL_POLICY_INVALID",
    `policy must be { steps: [{ approvers: { permission, role, team, users${manager ? ", manager" : ""} }, required, escalateAfter, escalateTo }], mode, selfApproval, expiresIn${manager ? ", managerOf" : ""} }`,
    "22023",
  );

  // A signed-in user files a request without an organization for a subject
  // type in options.tenantless; every other request needs one.
  const tenantless = (name: string): string =>
    tenantlessTypes(ctx).length === 0
      ? ""
      : ` or (${name}.tenant is null and ${tenantlessType(ctx, `${name}.subject_type`)} and auth.uid() is not null)`;

  const tenantRequired = (name: string): string =>
    tenantlessTypes(ctx).length === 0
      ? ""
      : `
  if ${name}.tenant is null and not ${tenantlessType(ctx, `${name}.subject_type`)} then
    ${fail("APPROVAL_TENANT_REQUIRED", "a request for this subject type needs an organization", "22023")}
  end if;`;

  return `
-- What a request for the subject type and action would need right now, with
-- subject as the request payload the tenant policies' conditions read; null
-- when nothing is required.
create or replace function ${fn("approval_requirement")}(tenant ${ctx.idType}, subject_type text, action text, subject jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_policy jsonb;
begin
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", "approval_requirement.tenant", request)}${tenantless("approval_requirement")}) then
    ${fail("APPROVAL_FORBIDDEN", "checking an approval requirement needs approvals.request")}
  end if;
  v_policy := ${fn("approval_effective_policy")}(approval_requirement.tenant, approval_requirement.subject_type, approval_requirement.action, approval_requirement.subject);
  if v_policy is null or not ${required("v_policy")} then
    return null;
  end if;
  return v_policy || jsonb_build_object('mode', coalesce(v_policy ->> 'mode', 'authorize'));
end;
$$;
${userGrant(`${fn("approval_requirement")}(${ctx.idType}, text, text, jsonb)`)}

-- An app's own policy for one request, tightened by the policy the request
-- would get anyway (base, null when there is none): steps add up, the stricter
-- mode wins, self-approval needs both to allow it and the shorter expiry
-- applies. It never loosens base.
create or replace function ${fn("approval_policy_tighten")}(base jsonb, own jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_step jsonb;
  v_who jsonb;
  v_mode text := coalesce(approval_policy_tighten.own ->> 'mode', 'authorize');
  v_steps jsonb := coalesce(approval_policy_tighten.own -> 'steps', '[]'::jsonb);
  v_level integer;
  v_expires interval;
begin
  if jsonb_typeof(approval_policy_tighten.own) is distinct from 'object'
    or jsonb_typeof(v_steps) <> 'array' or jsonb_array_length(v_steps) > 20
    or v_mode not in ('confirm', 'authorize')
    or (approval_policy_tighten.own ? 'selfApproval' and jsonb_typeof(approval_policy_tighten.own -> 'selfApproval') <> 'boolean')
    or (approval_policy_tighten.own ? 'managerOf' and ${manager ? "jsonb_typeof(approval_policy_tighten.own -> 'managerOf') <> 'string'" : "true"})
    or (approval_policy_tighten.own ->> 'expiresIn' is not null and (approval_policy_tighten.own ->> 'expiresIn')::interval <= interval '0') then
    ${ownInvalid}
  end if;
${stepsCheck("v_steps", ownInvalid, manager)}
  v_steps := ${allUsersCounted("v_steps")};
  v_expires := (approval_policy_tighten.own ->> 'expiresIn')::interval;
  if approval_policy_tighten.base is null then
    return jsonb_build_object(
      'steps', v_steps,
      'selfApproval', coalesce((approval_policy_tighten.own ->> 'selfApproval')::boolean, false),
      'expiresIn', v_expires::text, 'run', null
    ) || case when v_mode = 'confirm' then '{"mode": "confirm"}'::jsonb else '{}'::jsonb end
      || case when approval_policy_tighten.own ? 'managerOf' then jsonb_build_object('managerOf', approval_policy_tighten.own -> 'managerOf') else '{}'::jsonb end;
  end if;
  v_level := greatest(
    ${level("coalesce(approval_policy_tighten.base ->> 'mode', 'authorize')", "coalesce(approval_policy_tighten.base -> 'steps', '[]'::jsonb)")},
    ${level("v_mode", "v_steps")}
  );
  return approval_policy_tighten.base || jsonb_build_object(
    'steps', coalesce(approval_policy_tighten.base -> 'steps', '[]'::jsonb) || v_steps,
    'selfApproval', coalesce((approval_policy_tighten.base ->> 'selfApproval')::boolean, false) and coalesce((approval_policy_tighten.own ->> 'selfApproval')::boolean, false),
    'expiresIn', least((approval_policy_tighten.base ->> 'expiresIn')::interval, v_expires)::text,
    'mode', case when v_level = 1 then 'confirm' else 'authorize' end
  ) || case when approval_policy_tighten.own ? 'managerOf' then jsonb_build_object('managerOf', approval_policy_tighten.own -> 'managerOf') else '{}'::jsonb end;
exception
  when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    ${ownInvalid}
end;
$$;
revoke execute on function ${fn("approval_policy_tighten")}(jsonb, jsonb) from public, anon, authenticated;

drop function if exists ${fn("request_approval")}(${args});
drop function if exists ${fn("request_approval")}(${args}, jsonb);
drop function if exists ${fn("request_approval")}(${otherNew});
drop function if exists ${fn("request_approval")}(${args}${fields.type}, text);
drop function if exists ${fn("request_approval")}(${otherNew}, jsonb, uuid);
-- fingerprint: the hex SHA-256 of the request's canonical form, which
-- consume_approval checks before the approved action runs. The service role
-- may pass its own policy, which only tightens the configured and stored ones,
-- and requested_by, the user it files for, who can't approve it.
create or replace function ${fn("request_approval")}(tenant ${ctx.idType}, subject_type text, subject_id text, action text, reason text default null, payload jsonb default '{}'::jsonb${fields.param}, fingerprint text default null, policy jsonb default null, requested_by uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_policy jsonb := ${fn("approval_effective_policy")}(request_approval.tenant, request_approval.subject_type, request_approval.action, coalesce(request_approval.payload, '{}'::jsonb));
  v_service boolean := ${SERVICE_CALLER};
  v_result jsonb;
  v_req ${requests}%rowtype;
begin
  if request_approval.policy is not null and not v_service then
    ${fail("APPROVAL_FORBIDDEN", "only the service role files a request under its own policy")}
  end if;
  if request_approval.requested_by is not null and not v_service and request_approval.requested_by is distinct from auth.uid() then
    ${fail("APPROVAL_FORBIDDEN", "only the service role files a request for another user")}
  end if;
  if request_approval.policy is not null then
    v_policy := ${fn("approval_policy_tighten")}(v_policy, request_approval.policy);
  end if;
  if v_policy is null then
    ${fail("APPROVAL_POLICY_UNKNOWN", "no approval policy for this subject type and action", "22023")}
  end if;${tenantRequired("request_approval")}
  if not (v_service or (${ctx.can("tenant", "request_approval.tenant", request)} and ${subjectWrite})${tenantless("request_approval")}) then
    ${fail("APPROVAL_FORBIDDEN", "not allowed to request approval for this record")}
  end if;
  if not ${required("v_policy")} then
    ${fail("APPROVAL_NOT_REQUIRED", "no approval is required for this request", "22023")}
  end if;
  if request_approval.fingerprint is not null and request_approval.fingerprint !~ '^[0-9a-f]{64}$' then
    ${fail("APPROVAL_FINGERPRINT_INVALID", "fingerprint must be a lowercase hex SHA-256", "22023")}
  end if;${
    fingerprinted
      ? ""
      : `
  if request_approval.fingerprint is not null then
    ${fail("APPROVAL_FINGERPRINT_UNSUPPORTED", "this approval requests table has no fingerprint column", "22023")}
  end if;`
  }
  v_result := ${fn("open_approval")}(request_approval.tenant, request_approval.subject_type, request_approval.subject_id, request_approval.action, v_policy, request_approval.reason, request_approval.payload, coalesce(request_approval.requested_by, auth.uid()));${
    fingerprinted
      ? `
  if request_approval.fingerprint is not null then
    update ${requests} x set ${c("fingerprint")} = request_approval.fingerprint
    where x.${c("id")} = (v_result ->> 'id')::uuid and x.${c("status")} = 'pending';
  end if;`
      : ""
  }${
    extras.length === 0
      ? ""
      : `
${writeExtraColumns(requests, extras, "request_approval.fields", `x.${c("id")} = (v_result ->> 'id')::uuid`, "v_req")}`
  }
  select * into v_req from ${requests} x where x.${c("id")} = (v_result ->> 'id')::uuid;
  if found then
    return ${json("v_req")};
  end if;
  return v_result;
end;
$$;
${userGrant(`${fn("request_approval")}(${args}${fields.type}, text, jsonb, uuid)`)}`;
}

function consumeSql(
  ctx: BlockSqlContext,
  helpers: ApprovalRequestHelpers,
): string {
  const fn = (name: string): string => ctx.fn(name);
  const requests = ctx.table("requests");
  const c = (column: string): string => ctx.col("requests", column);
  const has = (column: string): boolean => ctx.has("requests", column);
  const { json, notFound, record } = helpers;
  const { manage } = helpers.permissions;

  const body = has("consumedAt")
    ? `
  select * into v_req from ${requests} r where r.${c("id")} = consume_approval.request_id for update;
  if not found then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or coalesce(v_req.${c("requestedBy")} = auth.uid(), false) or ${ctx.can("tenant", `v_req.${c("tenant")}`, manage)}) then
    ${notFound}
  end if;
  if v_req.${c("consumedAt")} is not null then
    ${fail("APPROVAL_CONSUMED", "this approval was already used", "22023")}
  end if;
  if v_req.${c("status")} <> 'approved' then
    ${fail("APPROVAL_NOT_APPROVED", "this request is not approved", "22023")}
  end if;
  if ${has("fingerprint") ? `v_req.${c("fingerprint")}` : "null::text"} is distinct from consume_approval.fingerprint then
    ${fail("APPROVAL_FINGERPRINT_MISMATCH", "the request changed after it was approved; ask for approval again", "22023")}
  end if;
  update ${requests} r set ${c("consumedAt")} = now()
    where r.${c("id")} = v_req.${c("id")} returning * into v_req;
  ${record("approval.consumed", "v_req", true)}
  return ${json("v_req")};`
    : `
  ${fail("APPROVAL_CONSUME_UNSUPPORTED", "this approval requests table has no consumed_at column", "22023")}`;

  return `
-- Uses an approved request once, right before the approved action runs. The
-- fingerprint must match the one the request was filed with, so an approval
-- never covers a request that changed after it was decided.
create or replace function ${fn("consume_approval")}(request_id uuid, fingerprint text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_req ${requests}%rowtype;
begin${body}
end;
$$;
${userGrant(`${fn("consume_approval")}(uuid, text)`)}`;
}

/**
 * The effective policy, the requirement check, request_approval,
 * consume_approval and, with `options.tenantPolicies`, the tenant policies.
 */
export function approvalsTenantSql(
  ctx: BlockSqlContext,
  helpers: ApprovalRequestHelpers,
): string {
  return `${tenantPoliciesOn(ctx) ? tenantPoliciesSql(ctx, helpers) : ""}
${effectivePolicySql(ctx)}
${requestSql(ctx, helpers)}
${consumeSql(ctx, helpers)}`;
}

/** The contract of the functions this file renders. */
export function approvalsTenantContract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "approval_requirement",
      args: ["{id}", "text", "text", "jsonb"],
      returns: "jsonb",
    },
    { name: "consume_approval", args: ["uuid", "text"], returns: "jsonb" },
    ...(tenantPoliciesOn(ctx)
      ? [
          {
            name: "save_approval_policy",
            args: ["{id}", "jsonb"],
            returns: "jsonb",
          },
          {
            name: "remove_approval_policy",
            args: ["uuid"],
            returns: "boolean",
          },
          {
            name: "list_approval_policies",
            args: ["{id}", "text", "integer"],
            returns: "jsonb",
          },
        ]
      : []),
  ];
}
