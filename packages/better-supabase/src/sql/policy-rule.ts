import type { Policy, PolicyInput } from "./policy.ts";

import { maskSql, policy, readPolicies, renderPolicy } from "./policy.ts";

/** A comparison a rule can make against a column. */
export type RuleOperator = "=" | "<>" | "<" | "<=" | ">" | ">=";

export type RuleValue = string | number | boolean;

/**
 * The policy DSL: a small tree that renders to a policy over the four `bsb.*`
 * functions and reads back from the `@bsb rule` comment.
 */
export type Rule =
  | { readonly kind: "public" }
  | { readonly kind: "owner"; readonly column: string }
  | { readonly kind: "member"; readonly column: string }
  | {
      readonly kind: "can";
      readonly column: string;
      readonly permission: string;
    }
  | {
      readonly kind: "compare";
      readonly column: string;
      readonly op: RuleOperator;
      readonly value: RuleValue;
    }
  | { readonly kind: "null"; readonly column: string; readonly isNull: boolean }
  | { readonly kind: "and"; readonly rules: readonly Rule[] }
  | { readonly kind: "or"; readonly rules: readonly Rule[] }
  | { readonly kind: "not"; readonly rule: Rule };

/** The only functions a policy may call. */
export const POLICY_FUNCTIONS: readonly string[] = [
  "bsb.is_member",
  "bsb.can",
  "bsb.owns",
  "bsb.uid",
];

const OPERATORS: ReadonlySet<string> = new Set([
  "=",
  "<>",
  "<",
  "<=",
  ">",
  ">=",
]);

const IDENTIFIER = /^[a-z_][a-z0-9_$]*$/i;

function column(name: string): string {
  if (!IDENTIFIER.test(name)) {
    throw new Error(`Rule column "${name}" is not a plain identifier.`);
  }

  return `"${name}"`;
}

function literal(value: RuleValue): string {
  if (typeof value === "string") {
    return `'${value.replaceAll("'", "''")}'`;
  }

  if (typeof value === "number" && !Number.isFinite(value)) {
    throw new TypeError("Rule values must be finite numbers.");
  }

  return String(value);
}

/** The SQL expression a rule renders to. */
export function renderRule(rule: Rule): string {
  switch (rule.kind) {
    case "public": {
      return "true";
    }

    case "owner": {
      return `bsb.owns(${column(rule.column)})`;
    }

    case "member": {
      return `bsb.is_member(${column(rule.column)})`;
    }

    case "can": {
      return `bsb.can(${column(rule.column)}, ${literal(rule.permission)})`;
    }

    case "compare": {
      if (!OPERATORS.has(rule.op)) {
        throw new Error(`Unknown rule operator "${rule.op}".`);
      }

      return `${column(rule.column)} ${rule.op} ${literal(rule.value)}`;
    }

    case "null": {
      return `${column(rule.column)} is ${rule.isNull ? "" : "not "}null`;
    }

    case "and":
    case "or": {
      if (rule.rules.length === 0) {
        return rule.kind === "and" ? "true" : "false";
      }

      return rule.rules
        .map((child) => `(${renderRule(child)})`)
        .join(` ${rule.kind} `);
    }

    case "not": {
      return `not (${renderRule(rule.rule)})`;
    }

    default: {
      const never: never = rule;

      return never;
    }
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Whether `value` is a well-formed rule tree. */
export function isRule(value: unknown): value is Rule {
  if (!isRecord(value)) {
    return false;
  }

  const { kind } = value;
  const col = typeof value["column"] === "string";

  switch (kind) {
    case "public": {
      return true;
    }

    case "owner":
    case "member": {
      return col;
    }

    case "can": {
      return col && typeof value["permission"] === "string";
    }

    case "compare": {
      const v = value["value"];

      return (
        col &&
        typeof value["op"] === "string" &&
        OPERATORS.has(value["op"]) &&
        (typeof v === "string" ||
          typeof v === "boolean" ||
          (typeof v === "number" && Number.isFinite(v)))
      );
    }

    case "null": {
      return col && typeof value["isNull"] === "boolean";
    }

    case "and":
    case "or": {
      const { rules } = value;

      return Array.isArray(rules) && rules.every(isRule);
    }

    case "not": {
      return isRule(value["rule"]);
    }

    default: {
      return false;
    }
  }
}

const RULE_COMMENT = /^-- @bsb rule (.+)$/;

/** The input of a policy built from rules. */
export interface RulePolicyInput extends Omit<PolicyInput, "using" | "check"> {
  readonly using?: Rule;
  readonly check?: Rule;
}

/** A policy and the rules it was built from. */
export interface RulePolicy {
  readonly policy: Policy;
  readonly using: Rule | null;
  readonly check: Rule | null;
}

/** Builds a policy from rule trees. */
export function rulePolicy(input: RulePolicyInput): RulePolicy {
  const { using, check, ...rest } = input;

  return {
    policy: policy({
      ...rest,
      ...(using === undefined ? {} : { using: renderRule(using) }),
      ...(check === undefined ? {} : { check: renderRule(check) }),
    }),
    using: using ?? null,
    check: check ?? null,
  };
}

/**
 * The statement for a rule policy, with the `-- @bsb rule` comment that
 * {@link readRulePolicies} reads back.
 */
export function renderRulePolicy(
  built: RulePolicy,
  options: { readonly drop?: boolean } = {},
): string {
  const meta = JSON.stringify({ using: built.using, check: built.check });

  const sql = renderPolicy(built.policy, options);
  const at = sql.indexOf("create policy");

  return `${sql.slice(0, at)}-- @bsb rule ${meta}\n${sql.slice(at)}`;
}

/** A policy that carries a rule comment, with the rules recovered. */
export interface ReadRulePolicy extends RulePolicy {
  /** True when the SQL still renders from the rules, false once hand-edited. */
  readonly inSync: boolean;
}

function parseMeta(
  text: string,
): { using: Rule | null; check: Rule | null } | undefined {
  let data: unknown;

  try {
    data = JSON.parse(text);
  } catch {
    return undefined;
  }

  if (!isRecord(data)) {
    return undefined;
  }

  const using = data["using"] ?? null;
  const check = data["check"] ?? null;

  if (
    (using !== null && !isRule(using)) ||
    (check !== null && !isRule(check))
  ) {
    return undefined;
  }

  return { using, check };
}

/**
 * Policies in `sql` that carry an `@bsb rule` comment directly above them.
 * `inSync` says whether the policy still matches what its rules render to.
 */
export function readRulePolicies(sql: string): ReadRulePolicy[] {
  const found: ReadRulePolicy[] = [];

  for (const read of readPolicies(sql)) {
    const lines = sql.slice(0, read.span[0]).trimEnd().split("\n");
    const comment = RULE_COMMENT.exec(lines.at(-1)?.trim() ?? "");
    const meta = comment?.[1] === undefined ? undefined : parseMeta(comment[1]);

    if (meta !== undefined) {
      const { policy: parsed } = read;

      const expected = rulePolicy({
        table: parsed.table,
        name: parsed.name,
        command: parsed.command,
        roles: parsed.roles,
        permissive: parsed.permissive,
        ...(meta.using === null ? {} : { using: meta.using }),
        ...(meta.check === null ? {} : { check: meta.check }),
      }).policy;

      found.push({
        policy: parsed,
        using: meta.using,
        check: meta.check,
        inSync:
          expected.using === parsed.using && expected.check === parsed.check,
      });
    }
  }

  return found;
}

const SQL_WORDS = new Set([
  "and",
  "or",
  "not",
  "in",
  "any",
  "all",
  "exists",
  "select",
  "from",
  "where",
  "is",
  "null",
  "true",
  "false",
  "between",
  "like",
  "ilike",
  "case",
  "when",
  "then",
  "else",
  "end",
  "using",
  "check",
  "on",
  "as",
]);

const CALL = /([a-z_][\w$]*(?:\s*\.\s*[a-z_][\w$]*)?)\s*\(/gi;

/**
 * The functions a policy calls that are not in {@link POLICY_FUNCTIONS},
 * lowercased and without spaces. An empty list means the policy only uses the
 * `bsb.*` functions.
 */
export function disallowedPolicyCalls(built: Policy): string[] {
  const bad = new Set<string>();

  for (const body of [built.using, built.check]) {
    if (body === null) {
      continue;
    }

    const masked = maskSql(body, { dollarBodies: "mask" });

    for (const match of masked.matchAll(CALL)) {
      const name = (match[1] ?? "").replaceAll(/\s+/g, "").toLowerCase();

      if (!SQL_WORDS.has(name) && !POLICY_FUNCTIONS.includes(name)) {
        bad.add(name);
      }
    }
  }

  return [...bad].toSorted();
}

/** Options for {@link policyFunctionsSql}. */
export interface PolicyFunctionsOptions {
  /** Set-returning function that lists the caller's tenant ids. */
  readonly memberships?: string;
  /** Function `(scope, scope_id, permission)` that answers a permission. */
  readonly permission?: string;
  /** Scope name `bsb.can` passes to the permission function. */
  readonly scope?: string;
}

/**
 * The `bsb` schema and the four functions policies may call. `uid` and `owns`
 * are fixed; `is_member` and `can` delegate to the functions named in the
 * options, so a library or your own tables can answer them.
 */
export function policyFunctionsSql(
  options: PolicyFunctionsOptions = {},
): string {
  const memberships =
    options.memberships ?? "better_supabase.member_organization_ids()";

  const permission = options.permission ?? "better_supabase.can";
  const scope = (options.scope ?? "organization").replaceAll("'", "''");

  return `create schema if not exists bsb;
grant usage on schema bsb to anon, authenticated, service_role;

create or replace function bsb.uid()
returns uuid
language sql
stable
as $$ select auth.uid() $$;

create or replace function bsb.owns(owner uuid)
returns boolean
language sql
stable
as $$ select owner is not null and owner = bsb.uid() $$;

create or replace function bsb.is_member(tenant uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$ select tenant in (select * from ${memberships}) $$;

create or replace function bsb.can(tenant uuid, permission_key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$ select ${permission}('${scope}', tenant, permission_key) $$;

revoke execute on function bsb.uid(), bsb.owns(uuid), bsb.is_member(uuid), bsb.can(uuid, text) from public;
grant execute on function bsb.uid(), bsb.owns(uuid), bsb.is_member(uuid), bsb.can(uuid, text) to anon, authenticated, service_role;
`;
}
