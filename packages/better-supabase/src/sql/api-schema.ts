import { sqlIdent } from "../core/template.ts";

/** `sql.modules.<module>.api`, resolved. */
export interface ModuleApi {
  readonly schema: string;
  /** Function names to wrap; every function granted to the API roles when missing. */
  readonly functions?: readonly string[];
}

interface Argument {
  readonly mode: "in" | "out" | "inout" | "variadic";
  readonly declaration: string;
  readonly type: string;
}

interface Signature {
  readonly name: string;
  readonly args: readonly Argument[];
  readonly returns: string;
}

/** The roles PostgREST runs a request as. */
const API_ROLES = new Set(["anon", "authenticated", "service_role"]);
const isMode = (word: string): word is Argument["mode"] =>
  word === "in" || word === "out" || word === "inout" || word === "variadic";
const TYPE_STARTS = new Set([
  "double",
  "timestamp",
  "time",
  "character",
  "bit",
  "interval",
]);

const normalize = (type: string): string =>
  type.replaceAll(/\s+/g, " ").replaceAll('"', "").trim().toLowerCase();

/** Splits on commas outside parentheses and quotes. */
function splitTopLevel(text: string): string[] {
  const parts: string[] = [];
  let depth = 0;
  let quote: string | undefined;
  let start = 0;
  for (let i = 0; i < text.length; i++) {
    const char = text[i]!;
    if (quote) {
      if (char === quote) quote = undefined;
    } else if (char === "'" || char === '"') quote = char;
    else if (char === "(" || char === "[") depth++;
    else if (char === ")" || char === "]") depth--;
    else if (char === "," && depth === 0) {
      parts.push(text.slice(start, i));
      start = i + 1;
    }
  }
  const last = text.slice(start);
  if (last.trim() !== "") parts.push(last);
  return parts.map((part) => part.trim());
}

/** The end of the parenthesized list that opens at `open`. */
function closing(text: string, open: number): number {
  let depth = 0;
  let quote: string | undefined;
  for (let i = open; i < text.length; i++) {
    const char = text[i]!;
    if (quote) {
      if (char === quote) quote = undefined;
    } else if (char === "'" || char === '"') quote = char;
    else if (char === "(") depth++;
    else if (char === ")") {
      depth--;
      if (depth === 0) return i;
    }
  }
  return -1;
}

function argument(text: string): Argument {
  const withoutDefault = text.split(/\s+default\s+|\s*=\s*/i)[0]!.trim();
  const words = withoutDefault.split(/\s+/);
  let mode: Argument["mode"] = "in";
  const first = words[0]!.toLowerCase();
  if (isMode(first) && words.length > 1) {
    mode = first;
    words.shift();
  }
  const named = words.length > 1 && !TYPE_STARTS.has(words[0]!.toLowerCase());
  const type = (named ? words.slice(1) : words).join(" ");
  return { mode, declaration: text, type };
}

function signatures(sql: string, schema: string): Signature[] {
  const ident = `(?:"${schema}"|${schema})`;
  const create = new RegExp(
    `create\\s+(?:or\\s+replace\\s+)?function\\s+${ident}\\.(?:"([^"]+)"|([a-z_][a-z0-9_]*))\\s*\\(`,
    "gi",
  );
  const found: Signature[] = [];
  for (const match of sql.matchAll(create)) {
    const open = match.index + match[0].length - 1;
    const close = closing(sql, open);
    if (close === -1) continue;
    const rest = sql.slice(close + 1);
    const returns =
      /^\s*returns\s+([\s\S]*?)\n(?=\s*(?:language|stable|volatile|immutable|security|set|as|strict|parallel|cost|rows)\b)/i.exec(
        rest,
      );
    if (!returns) continue;
    found.push({
      name: (match[1] ?? match[2])!,
      args: splitTopLevel(sql.slice(open + 1, close)).map(argument),
      returns: returns[1]!.trim(),
    });
  }
  return found;
}

interface Grant {
  readonly name: string;
  readonly types: readonly string[];
  readonly roles: readonly string[];
}

function apiGrants(sql: string, schema: string): Grant[] {
  const ident = `(?:"${schema}"|${schema})`;
  const grant = new RegExp(
    `grant\\s+execute\\s+on\\s+function\\s+${ident}\\.(?:"([^"]+)"|([a-z_][a-z0-9_]*))\\s*\\(([^)]*)\\)\\s+to\\s+([^;]+);`,
    "gi",
  );
  return [...sql.matchAll(grant)].flatMap((match) => {
    const roles = match[4]!
      .split(",")
      .map((role) => role.trim().replace(/^"(.*)"$/, "$1"))
      .filter((role) => API_ROLES.has(role));
    if (roles.length === 0) return [];
    return [
      {
        name: (match[1] ?? match[2])!,
        types: splitTopLevel(match[3]!).map(normalize),
        roles,
      },
    ];
  });
}

const inputs = (signature: Signature): Argument[] =>
  signature.args.filter((arg) => arg.mode !== "out");

function wrapper(
  signature: Signature,
  source: string,
  api: string,
  grant: Grant,
): string {
  const target = `${sqlIdent(api)}.${sqlIdent(signature.name)}`;
  const params = inputs(signature)
    .map((arg, index) =>
      arg.mode === "variadic" ? `variadic $${index + 1}` : `$${index + 1}`,
    )
    .join(", ");
  const call = `${sqlIdent(source)}.${sqlIdent(signature.name)}(${params})`;
  const set = /^(setof\s|table\s*\()/i.test(signature.returns);
  const types = grant.types.join(", ");
  return `create or replace function ${target}(${signature.args.map((arg) => arg.declaration).join(", ")})
returns ${signature.returns}
language sql
security invoker
set search_path = ''
as $$ select ${set ? "* from " : ""}${call} $$;
revoke execute on function ${target}(${types}) from public;
grant execute on function ${target}(${types}) to ${grant.roles.join(", ")};`;
}

/**
 * `security invoker` wrappers in `api.schema` for the module functions that
 * `anon`, `authenticated` or `service_role` may execute, with the same names,
 * arguments and grants (to those roles only). Expose the API schema to the
 * Data API instead of the module schema, which also holds helpers that only
 * policies should call. A server that reaches the database only through
 * PostgREST then calls the service functions, such as `flag_definitions`,
 * with a service-role client. The module's `internal` helpers (granted only
 * so its policies and triggers can call them as the client) get no wrapper,
 * and a wrapper an earlier version wrote for one is dropped.
 */
export function apiWrappers(
  sql: string,
  source: string,
  api: ModuleApi,
  module: string,
  internal: readonly string[] = [],
): string {
  if (api.schema === source) {
    throw new TypeError(
      `sql.modules.${module}.api: the API schema must differ from the module schema ${source}`,
    );
  }
  const defined = signatures(sql, source);
  const granted = apiGrants(sql, source);
  const helpers = granted.filter((grant) => internal.includes(grant.name));
  const grants = granted.filter(
    (grant) =>
      !internal.includes(grant.name) &&
      (!api.functions || api.functions.includes(grant.name)),
  );
  for (const name of api.functions ?? []) {
    if (internal.includes(name)) {
      throw new TypeError(
        `sql.modules.${module}.api.functions: ${name} is a helper the module's policies and triggers call, not an entry point for the Data API`,
      );
    }
    if (!grants.some((grant) => grant.name === name)) {
      throw new TypeError(
        `sql.modules.${module}.api.functions: ${name} is not a ${module} function that anon, authenticated or service_role may execute`,
      );
    }
  }
  const schema = sqlIdent(api.schema);
  const dropped = [
    ...new Map(
      helpers.map((grant) => [
        `${grant.name}(${grant.types.join(", ")})`,
        `drop function if exists ${schema}.${sqlIdent(grant.name)}(${grant.types.join(", ")});`,
      ]),
    ).values(),
  ];
  if (grants.length === 0 && dropped.length === 0) return "";
  const statements = grants.map((grant) => {
    const signature = defined.find(
      (entry) =>
        entry.name === grant.name &&
        inputs(entry).length === grant.types.length &&
        inputs(entry).every(
          (arg, index) => normalize(arg.type) === grant.types[index],
        ),
    );
    if (!signature) {
      throw new TypeError(
        `sql.modules.${module}.api: found no definition of ${grant.name}(${grant.types.join(", ")}) to wrap`,
      );
    }
    return wrapper(signature, source, api.schema, grant);
  });
  return `
-- sql.modules.${module}.api: entry points for the Data API.
create schema if not exists ${schema};
grant usage on schema ${schema} to anon, authenticated, service_role;
${dropped.length > 0 ? `\n-- Helpers for the module's policies and triggers have no entry point.\n${dropped.join("\n")}\n` : ""}
${statements.join("\n\n")}
`;
}
