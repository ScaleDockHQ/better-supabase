import type { Persona, SandboxResult } from "./sandbox.ts";

/** Runs one statement as a persona. */
export type RunAs = (
  persona: Persona,
  sql: string,
  params: readonly unknown[],
) => Promise<SandboxResult>;

const FILTERS: Readonly<Record<string, string>> = {
  eq: "=",
  neq: "<>",
  gt: ">",
  gte: ">=",
  lt: "<",
  lte: "<=",
  like: "like",
  ilike: "ilike",
};

const RESERVED = new Set([
  "select",
  "order",
  "limit",
  "offset",
  "columns",
  "on_conflict",
]);

const quote = (name: string): string => `"${name.replaceAll('"', '""')}"`;

interface Problem {
  readonly status: number;
  readonly code: string;
  readonly message: string;
}

const bad = (message: string, code = "PGRST100"): Problem => ({
  status: 400,
  code,
  message,
});

function json(status: number, body: unknown): Response {
  return Response.json(body, { status });
}

function problem(error: Problem): Response {
  return json(error.status, {
    code: error.code,
    message: error.message,
    details: null,
    hint: null,
  });
}

function decodeClaims(token: string): Record<string, unknown> | undefined {
  const [, payload] = token.split(".");

  if (payload === undefined) {
    return undefined;
  }

  try {
    const text = atob(payload.replaceAll("-", "+").replaceAll("_", "/"));
    const parsed: unknown = JSON.parse(text);

    return typeof parsed === "object" &&
      parsed !== null &&
      !Array.isArray(parsed)
      ? Object.fromEntries(Object.entries(parsed))
      : undefined;
  } catch {
    return undefined;
  }
}

/**
 * The persona a request's bearer token names. The sandbox decodes the payload
 * and does not verify the signature.
 */
export function personaOf(request: Request): Persona {
  const header = request.headers.get("authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : "";
  const claims = token === "" ? undefined : decodeClaims(token);

  if (claims === undefined) {
    return { role: "anon" };
  }

  const { sub, role, ...rest } = claims;

  const known =
    role === "anon" || role === "authenticated" || role === "service_role"
      ? role
      : undefined;

  return {
    ...(typeof sub === "string" ? { sub } : {}),
    ...(known === undefined ? {} : { role: known }),
    claims: rest,
  };
}

interface ColumnInfo {
  readonly type: string;
  readonly array: boolean;
}

async function columnsOf(
  run: RunAs,
  table: string,
): Promise<ReadonlyMap<string, ColumnInfo> | undefined> {
  // Column names come from the catalog as the owner, not as the persona, so
  // a table the persona can't read still answers 401 or 403 from its own query.
  const result = await run(
    { role: "service_role" },
    `select a.attname as name, t.typname as type, t.typcategory = 'A' as array
       from pg_attribute a
       join pg_class c on c.oid = a.attrelid
       join pg_namespace n on n.oid = c.relnamespace
       join pg_type t on t.oid = a.atttypid
      where n.nspname = 'public' and c.relname = $1
        and c.relkind in ('r', 'p', 'v', 'm')
        and a.attnum > 0 and not a.attisdropped`,
    [table],
  );

  if (!result.ok || result.rows.length === 0) {
    return undefined;
  }

  const columns = new Map<string, ColumnInfo>();

  for (const row of result.rows) {
    if (
      typeof row === "object" &&
      row !== null &&
      "name" in row &&
      typeof row.name === "string" &&
      "type" in row &&
      typeof row.type === "string"
    ) {
      columns.set(row.name, {
        type: row.type,
        array: "array" in row && row.array === true,
      });
    }
  }

  return columns;
}

/** A value as the driver takes it for `column`. */
function bound(value: unknown, column: ColumnInfo | undefined): unknown {
  if (value === null || value === undefined) {
    return null;
  }

  if (column?.array === true && Array.isArray(value)) {
    return `{${value
      .map(
        (item) =>
          `"${String(item).replaceAll("\\", "\\\\").replaceAll('"', '\\"')}"`,
      )
      .join(",")}}`;
  }

  return typeof value === "object" ? JSON.stringify(value) : value;
}

class Builder {
  readonly params: unknown[] = [];

  add(value: unknown): string {
    this.params.push(value);

    return `$${String(this.params.length)}`;
  }
}

function conditionOf(
  column: string,
  expression: string,
  columns: ReadonlyMap<string, ColumnInfo>,
  builder: Builder,
): string | Problem {
  const info = columns.get(column);

  if (info === undefined) {
    return bad(`Could not find the column ${column}.`, "42703");
  }

  let negate = false;
  let rest = expression;

  if (rest.startsWith("not.")) {
    negate = true;
    rest = rest.slice(4);
  }

  const dot = rest.indexOf(".");
  const op = dot === -1 ? rest : rest.slice(0, dot);
  const value = dot === -1 ? "" : rest.slice(dot + 1);
  const left = quote(column);
  let sql: string;

  if (op === "is") {
    const keyword = value.toLowerCase();

    if (!["null", "true", "false", "unknown"].includes(keyword)) {
      return bad(`Unsupported value for is: ${value}.`);
    }

    sql = `${left} is ${keyword}`;
  } else if (op === "in") {
    const inner = /^\((.*)\)$/u.exec(value)?.[1];

    if (inner === undefined) {
      return bad("in expects a parenthesized list.");
    }

    const items = inner
      .split(",")
      .map((item) => item.trim().replace(/^"(.*)"$/u, "$1"));

    sql = `${left} in (${items.map((item) => builder.add(item)).join(", ")})`;
  } else if (op in FILTERS) {
    const operator = FILTERS[op] ?? "=";

    const pattern =
      op === "like" || op === "ilike" ? value.replaceAll("*", "%") : value;

    sql = `${left} ${operator} ${builder.add(pattern)}`;
  } else {
    return bad(`Unsupported operator ${op}.`);
  }

  return negate ? `not (${sql})` : sql;
}

function whereOf(
  url: URL,
  columns: ReadonlyMap<string, ColumnInfo>,
  builder: Builder,
): string | Problem {
  const conditions: string[] = [];

  for (const [key, expression] of url.searchParams) {
    if (RESERVED.has(key)) {
      continue;
    }

    if (key === "or" || key === "and" || key === "not") {
      return bad(`${key} filters are not supported by the sandbox.`);
    }

    const condition = conditionOf(key, expression, columns, builder);

    if (typeof condition !== "string") {
      return condition;
    }

    conditions.push(condition);
  }

  return conditions.length === 0 ? "" : ` where ${conditions.join(" and ")}`;
}

function selectOf(
  url: URL,
  columns: ReadonlyMap<string, ColumnInfo>,
): string | Problem {
  const select = url.searchParams.get("select");

  if (select === null || select === "*") {
    return "*";
  }

  if (select.includes("(")) {
    return bad("Embedding is not supported by the sandbox.");
  }

  const names = select.split(",").map((name) => name.trim());
  const missing = names.find((name) => !columns.has(name));

  return missing === undefined
    ? names.map((name) => quote(name)).join(", ")
    : bad(`Could not find the column ${missing}.`, "42703");
}

function tailOf(
  url: URL,
  columns: ReadonlyMap<string, ColumnInfo>,
): string | Problem {
  let sql = "";
  const order = url.searchParams.get("order");

  if (order !== null) {
    const parts: string[] = [];

    for (const item of order.split(",")) {
      const [name = "", ...flags] = item.split(".");

      if (!columns.has(name)) {
        return bad(`Could not find the column ${name}.`, "42703");
      }

      parts.push(
        `${quote(name)}${flags.includes("desc") ? " desc" : ""}${
          flags.includes("nullsfirst")
            ? " nulls first"
            : flags.includes("nullslast")
              ? " nulls last"
              : ""
        }`,
      );
    }

    sql += ` order by ${parts.join(", ")}`;
  }

  for (const key of ["limit", "offset"] as const) {
    const value = url.searchParams.get(key);

    if (value !== null) {
      if (!/^\d+$/u.test(value)) {
        return bad(`${key} must be a number.`);
      }

      sql += ` ${key} ${value}`;
    }
  }

  return sql;
}

function statusOf(code: string, persona: Persona): number {
  switch (code) {
    case "42501": {
      return persona.sub === undefined && persona.role !== "service_role"
        ? 401
        : 403;
    }

    case "23505":
    case "23503":
    case "23P01": {
      return 409;
    }

    case "42P01":
    case "42883": {
      return 404;
    }

    default: {
      return 400;
    }
  }
}

async function readBody(request: Request): Promise<unknown> {
  const text = await request.text();

  return text === "" ? undefined : JSON.parse(text);
}

function isRow(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

async function writeRows(
  request: Request,
  table: string,
  columns: ReadonlyMap<string, ColumnInfo>,
  url: URL,
  builder: Builder,
): Promise<string | Problem> {
  let body: unknown;

  try {
    body = await readBody(request);
  } catch {
    return bad("The body is not valid JSON.", "PGRST102");
  }

  const returning = request.headers
    .get("prefer")
    ?.includes("return=representation")
    ? " returning *"
    : "";

  if (request.method === "POST") {
    const rows = (Array.isArray(body) ? body : [body]).filter((row) =>
      isRow(row),
    );

    if (rows.length === 0) {
      return bad(
        "The body must be a JSON object or an array of objects.",
        "PGRST102",
      );
    }

    const keys = [...new Set(rows.flatMap((row) => Object.keys(row)))];
    const unknown = keys.find((key) => !columns.has(key));

    if (unknown !== undefined) {
      return bad(
        `Could not find the ${unknown} column of ${table}.`,
        "PGRST204",
      );
    }

    if (keys.length === 0) {
      return `insert into public.${quote(table)} default values${returning}`;
    }

    const values = rows.map(
      (row) =>
        `(${keys
          .map((key) =>
            Object.hasOwn(row, key)
              ? builder.add(bound(row[key], columns.get(key)))
              : "default",
          )
          .join(", ")})`,
    );

    return `insert into public.${quote(table)} (${keys.map((key) => quote(key)).join(", ")}) values ${values.join(", ")}${returning}`;
  }

  // PATCH
  if (!isRow(body)) {
    return bad("The body must be a JSON object.", "PGRST102");
  }

  const keys = Object.keys(body);
  const unknown = keys.find((key) => !columns.has(key));

  if (unknown !== undefined) {
    return bad(`Could not find the ${unknown} column of ${table}.`, "PGRST204");
  }

  if (keys.length === 0) {
    return bad("There is nothing to update.", "PGRST102");
  }

  const sets = keys.map(
    (key) =>
      `${quote(key)} = ${builder.add(bound(body[key], columns.get(key)))}`,
  );

  const where = whereOf(url, columns, builder);

  return typeof where === "string"
    ? `update public.${quote(table)} set ${sets.join(", ")}${where}${returning}`
    : where;
}

async function callFunction(
  request: Request,
  name: string,
  persona: Persona,
  run: RunAs,
): Promise<Response> {
  let body: unknown;

  try {
    body = await readBody(request);
  } catch {
    return problem(bad("The body is not valid JSON.", "PGRST102"));
  }

  const args = isRow(body) ? Object.entries(body) : [];
  const builder = new Builder();

  const list = args
    .map(
      ([key, value]) =>
        `${quote(key)} => ${builder.add(bound(value, undefined))}`,
    )
    .join(", ");

  const result = await run(
    persona,
    `select * from public.${quote(name)}(${list})`,
    builder.params,
  );

  if (!result.ok) {
    return problem({
      status: statusOf(result.error.code, persona),
      code: result.error.code,
      message: result.error.message,
    });
  }

  const [first] = result.rows;

  if (
    result.rows.length === 1 &&
    isRow(first) &&
    Object.keys(first).length === 1 &&
    Object.hasOwn(first, name)
  ) {
    return json(200, first[name]);
  }

  return json(200, result.rows);
}

/**
 * A subset of PostgREST: `GET`, `POST`, `PATCH` and `DELETE` on
 * `/rest/v1/<table>` and `POST` on `/rest/v1/rpc/<function>`. With no `fixed`
 * persona the bearer token names one.
 */
export async function handleRest(
  request: Request,
  run: RunAs,
  fixed?: Persona,
): Promise<Response> {
  const persona = fixed ?? personaOf(request);
  const url = new URL(request.url);
  const path = url.pathname.replace(/^\/rest\/v1\/?/u, "").replace(/^\//u, "");

  const [name = "", extra] = path.split("/");
  const isRpc = name === "rpc";
  const target = isRpc ? (extra ?? "") : name;

  if (target === "" || !/^[\w$]+$/u.test(target)) {
    return problem({
      status: 404,
      code: "PGRST125",
      message: `Invalid path specified in request URL: ${url.pathname}`,
    });
  }

  if (isRpc) {
    return request.method === "POST"
      ? callFunction(request, target, persona, run)
      : problem({
          status: 405,
          code: "PGRST101",
          message: "Functions take POST.",
        });
  }

  const columns = await columnsOf(run, target);

  if (columns === undefined) {
    return problem({
      status: 404,
      code: "PGRST205",
      message: `Could not find the table public.${target} in the schema cache`,
    });
  }

  const builder = new Builder();
  let sql: string | Problem;

  switch (request.method) {
    case "GET":
    case "HEAD": {
      const select = selectOf(url, columns);
      const where = whereOf(url, columns, builder);
      const tail = tailOf(url, columns);

      sql =
        [select, where, tail].find((part) => typeof part !== "string") ??
        `select ${String(select)} from public.${quote(target)}${String(where)}${String(tail)}`;
      break;
    }

    case "POST":
    case "PATCH": {
      sql = await writeRows(request, target, columns, url, builder);
      break;
    }

    case "DELETE": {
      const where = whereOf(url, columns, builder);

      const returning = request.headers
        .get("prefer")
        ?.includes("return=representation")
        ? " returning *"
        : "";

      sql =
        typeof where === "string"
          ? `delete from public.${quote(target)}${where}${returning}`
          : where;
      break;
    }

    default: {
      return problem({
        status: 405,
        code: "PGRST101",
        message: `Unsupported HTTP method: ${request.method}`,
      });
    }
  }

  if (typeof sql !== "string") {
    return problem(sql);
  }

  const result = await run(persona, sql, builder.params);

  if (!result.ok) {
    return problem({
      status: statusOf(result.error.code, persona),
      code: result.error.code,
      message: result.error.message,
    });
  }

  const wantsRows =
    request.method === "GET" ||
    request.method === "HEAD" ||
    request.headers.get("prefer")?.includes("return=representation") === true;

  if (!wantsRows) {
    return new Response(null, {
      status: request.method === "POST" ? 201 : 204,
    });
  }

  const status = request.method === "POST" ? 201 : 200;

  if (
    request.headers
      .get("accept")
      ?.includes("application/vnd.pgrst.object+json") === true
  ) {
    if (result.rows.length !== 1) {
      return problem({
        status: 406,
        code: "PGRST116",
        message: "JSON object requested, multiple (or no) rows returned",
      });
    }

    return json(status, result.rows[0]);
  }

  return request.method === "HEAD"
    ? new Response(null, { status })
    : json(status, result.rows);
}
