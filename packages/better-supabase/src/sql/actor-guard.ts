import type { BlockSqlLayout } from "./module-types.ts";

import { fillTemplate, templatePlaceholders } from "../core/access-sql.ts";
import { SERVICE_CALLER } from "./shared.ts";

/**
 * Functions granted to `authenticated` that write, but a read-only support or
 * impersonation session may still call. Ending or starting the session is how
 * that session is left.
 */
export const WRITE_GUARD_ALLOWLIST: ReadonlySet<string> = new Set([
  "end_support_session",
  "start_support_session",
  "expire_support_sessions",
  // Runs for every request, including reads. It only counts the request.
  "check_request",
]);

/** The built-in check and the raise SQL-language functions call. */
export function actorWriteFunctions(): string {
  return `
create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;`;
}

/** The boolean expression a write checks. The provider template wins, alone. */
function actorMayWriteExpression(layout: BlockSqlLayout): string {
  const template = layout.accessProvider?.functions.actorMayWrite;

  if (template === undefined) {
    return "better_supabase.actor_may_write()";
  }

  const placeholders = templatePlaceholders(template);

  if (placeholders.length > 0) {
    throw new TypeError(
      `authorization.functions.actorMayWrite takes no placeholders, got ${placeholders.map((name) => `{${name}}`).join(", ")}`,
    );
  }

  return fillTemplate("authorization.functions.actorMayWrite", template, {});
}

const BUILTIN_ACTOR_MAY_WRITE = "better_supabase.actor_may_write()";

/** Swaps the built-in for the provider template so a write never calls both. */
function applyProviderCheck(sql: string, expression: string): string {
  if (expression === BUILTIN_ACTOR_MAY_WRITE) {
    return sql;
  }

  return sql.replaceAll(BUILTIN_ACTOR_MAY_WRITE, `(${expression})`);
}

const WRITE = /\b(insert\s+into|update\s+(?:only\s+)?["a-z_]|delete\s+from)\b/i;

/** Puts the read-only check on user-callable write functions and write policies. */
export function applyActorWriteGuards(
  sql: string,
  layout: BlockSqlLayout,
): string {
  const expression = actorMayWriteExpression(layout);

  const guarded = applyProviderCheck(
    guardPolicies(guardFunctions(sql, expression), expression),
    expression,
  );

  if (
    !guarded.includes("actor_may_write(") &&
    !guarded.includes("raise_actor_readonly(")
  ) {
    return guarded;
  }

  if (guarded.includes("function better_supabase.actor_may_write(")) {
    return guarded;
  }

  return `${actorWriteFunctions()}\n${guarded}`;
}

function guardFunctions(sql: string, expression: string): string {
  const granted = grantedFunctionNames(sql);
  let cursor = 0;
  let out = "";
  const start = /create\s+(?:or\s+replace\s+)?function\s+/gi;

  for (const match of sql.matchAll(start)) {
    const at = match.index;

    if (at < cursor) {
      continue;
    }

    const tagged = /as\s+(\$[a-zA-Z0-9_]*\$)/i.exec(sql.slice(at));

    if (tagged === null) {
      break;
    }

    const tag = tagged[1] ?? "$$";
    const headerEnd = at + tagged.index;
    const bodyStart = at + tagged.index + tagged[0].length;
    const bodyEnd = sql.indexOf(tag, bodyStart);

    if (bodyEnd === -1) {
      break;
    }

    out += sql.slice(cursor, bodyStart);
    const header = sql.slice(at, headerEnd);
    const name = functionName(header);
    const body = sql.slice(bodyStart, bodyEnd);

    const guard =
      name !== undefined &&
      granted.has(name) &&
      !WRITE_GUARD_ALLOWLIST.has(name) &&
      /\bsecurity\s+definer\b/i.test(header) &&
      WRITE.test(body) &&
      !body.includes("ACTOR_READ_ONLY") &&
      !body.includes("raise_actor_readonly()");

    out += guard
      ? injectGuard(body, expression, /\blanguage\s+sql\b/i.test(header))
      : body;
    cursor = bodyEnd;
  }

  return out + sql.slice(cursor);
}

function injectGuard(
  body: string,
  expression: string,
  languageSql: boolean,
): string {
  const begin = /\bbegin\b/i.exec(body);

  if (begin !== null) {
    const at = begin.index + begin[0].length;

    return `${body.slice(0, at)}\n  if not (${expression}) then\n    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';\n  end if;${body.slice(at)}`;
  }

  if (!languageSql) {
    return body;
  }

  return `\n  select better_supabase.raise_actor_readonly() where not (${expression});\n${body}`;
}

function functionName(header: string): string | undefined {
  const match =
    /function\s+(?:(?:"[^"]+"|[a-z_][\w$]*)\s*\.\s*)?(?:"([^"]+)"|([a-z_][\w$]*))\s*\(/i.exec(
      header,
    );

  return match?.[1] ?? match?.[2];
}

function grantedFunctionNames(sql: string): Set<string> {
  const names = new Set<string>();

  const grants =
    /grant\s+execute\s+on\s+function\s+((?:"[^"]+"|[a-z_][\w$]*)(?:\s*\.\s*(?:"[^"]+"|[a-z_][\w$]*))?)\s*\([^;]*?\)\s+to\s+([^;]+)/gi;

  for (const match of sql.matchAll(grants)) {
    const roles = match[2] ?? "";

    if (!/\bauthenticated\b/i.test(roles) && !/\banon\b/i.test(roles)) {
      continue;
    }

    const qualified = match[1] ?? "";
    const name = /(?:"([^"]+)"|([a-z_][\w$]*))\s*$/i.exec(qualified);
    const found = name?.[1] ?? name?.[2];

    if (found !== undefined) {
      names.add(found);
    }
  }

  return names;
}

function guardPolicies(sql: string, expression: string): string {
  return sql.replaceAll(/create\s+policy\b[\s\S]*?;/gi, (statement) => {
    if (!/\bfor\s+(insert|update|delete)\b/i.test(statement)) {
      return statement;
    }

    if (/\bfor\s+(all|select)\b/i.test(statement)) {
      return statement;
    }

    if (!/\bto\s+[^;]*\bauthenticated\b/i.test(statement)) {
      return statement;
    }

    return wrapClause(
      wrapClause(statement, "with check", expression),
      "using",
      expression,
    );
  });
}

function wrapClause(
  statement: string,
  keyword: string,
  expression: string,
): string {
  const re = new RegExp(`\\b${keyword}\\s*\\(`, "i");
  const match = re.exec(statement);

  if (match === null) {
    return statement;
  }

  const open = match.index + match[0].length - 1;
  const close = closingParen(statement, open);

  if (close === -1) {
    return statement;
  }

  const inner = statement.slice(open + 1, close);

  if (inner.includes("actor_may_write(")) {
    return statement;
  }

  return `${statement.slice(0, open + 1)}(${inner}) and (select ${expression})${statement.slice(close)}`;
}

/** The index of the `)` that closes the `(` at `open`, or -1. */
export function closingParen(text: string, open: number): number {
  let depth = 0;
  let quote: string | undefined;

  for (let i = open; i < text.length; i += 1) {
    const char = text[i]!;

    if (quote) {
      if (char === quote && text[i + 1] === quote) {
        i += 1;
      } else if (char === quote) {
        quote = undefined;
      }
    } else if (char === "'") {
      quote = char;
    } else if (char === "(") {
      depth += 1;
    } else if (char === ")") {
      depth -= 1;

      if (depth === 0) {
        return i;
      }
    }
  }

  return -1;
}

/**
 * `acting_member()`: the member a secret-key writer names in the `x-bsb-actor`
 * request header, for a service caller only. Any other caller gets null, so a
 * user cannot write the header to be recorded as someone else.
 */
export const ACTING_MEMBER: string = `-- The user a service caller acts for, from the x-bsb-actor header. Null for
-- every other caller, so the header cannot be spoofed with a user's token.
-- Only service_role may call it; the security definer functions and triggers
-- that record an actor call it as their owner.
create or replace function better_supabase.acting_member()
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  header text;
begin
  if not (${SERVICE_CALLER}) then
    return null;
  end if;
  header := nullif(current_setting('request.headers', true), '')::jsonb ->> 'x-bsb-actor';
  return case when header ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then header::uuid end;
exception when others then
  return null;
end;
$$;
revoke execute on function better_supabase.acting_member() from public, anon, authenticated;
grant execute on function better_supabase.acting_member() to service_role;`;
