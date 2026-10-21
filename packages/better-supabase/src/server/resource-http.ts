import type { ValidationIssue } from "../core/errors.ts";
import type { RequestContext } from "../core/plugin.ts";
import type { Result } from "../core/result.ts";
import type { TableMeta } from "../schema/types.ts";
import type { PlannedAction, ResourcePagination } from "../spec/resource.ts";
import type { ResourceInput } from "./resource-types.ts";

import { dbError } from "../core/errors.ts";
import { isRecord } from "../core/guards.ts";
import { err, ok } from "../core/result.ts";

const INTEGER = new Set(["int2", "int4", "int8"]);

export function keyValue(table: TableMeta, raw: unknown): Result<unknown> {
  const invalid = err(
    dbError(
      "invalid_input",
      `${JSON.stringify(raw)} is not a valid ${table.key} key`,
    ),
  );

  const column = table.columns[table.primaryKey[0]!];

  if (column && INTEGER.has(column.type)) {
    const value = typeof raw === "string" ? Number(raw) : raw;

    return typeof value === "number" && Number.isSafeInteger(value)
      ? ok(value)
      : invalid;
  }

  return typeof raw === "string" && raw !== "" ? ok(raw) : invalid;
}

/**
 * A cross-site browser request that needed no CORS preflight: a form post
 * riding on the session cookie. Bearer requests and JSON bodies (which need a
 * preflight) pass, as do requests without an `Origin` (not a browser).
 */
export function crossSiteSimpleRequest(request: Request): boolean {
  if (request.method === "GET" || request.method === "HEAD") {
    return false;
  }

  if (request.headers.has("authorization")) {
    return false;
  }

  const origin = request.headers.get("origin");

  if (!origin || origin === new URL(request.url).origin) {
    return false;
  }

  if (request.headers.get("sec-fetch-site") === "same-origin") {
    return false;
  }

  const type = request.headers.get("content-type") ?? "";

  return !/^application\/(?:[\w.+-]+\+)?json\b/iu.test(type);
}

export async function readBody(request: Request): Promise<Result<unknown>> {
  try {
    const body: unknown = await request.json();

    if (typeof body === "object" && body !== null && !Array.isArray(body)) {
      return ok(body);
    }
  } catch {
    // Reported below.
  }

  return err(
    dbError("invalid_input", "The request body must be a JSON object"),
  );
}

/** Any JSON body; an empty body is `undefined`. */
export async function readJson(request: Request): Promise<Result<unknown>> {
  const text = await request.text();

  if (text.trim() === "") {
    return ok(undefined);
  }

  try {
    return ok(JSON.parse(text));
  } catch {
    return err(dbError("invalid_input", "The request body must be JSON"));
  }
}

/** URL parameters as an object; a repeated name becomes an array. */
export function queryObject(
  query: ResourceInput["query"],
): Readonly<Record<string, unknown>> {
  if (!(query instanceof URLSearchParams)) {
    return query ?? {};
  }

  const values: Record<string, string | string[]> = {};

  for (const [name, value] of query) {
    const seen = values[name];
    values[name] =
      seen === undefined
        ? value
        : [...(Array.isArray(seen) ? seen : [seen]), value];
  }

  return values;
}

export function pageArgs(
  query: ResourceInput["query"],
  max: number,
  pagination: ResourcePagination,
): Result<
  { page: number; size: number } | { after: string | null; size: number }
> {
  const raw = (name: string): unknown => {
    const value: unknown =
      query instanceof URLSearchParams ? query.get(name) : query?.[name];

    return value === null || value === "" ? undefined : value;
  };

  const read = (name: string, fallback: number): number | undefined => {
    const value = raw(name);

    if (value === undefined) {
      return fallback;
    }

    const number = Number(value);

    return Number.isSafeInteger(number) && number >= 1 ? number : undefined;
  };

  const issues: ValidationIssue[] = [];
  const size = read("size", 50);

  if (size === undefined || size > max) {
    issues.push({ message: `Must be between 1 and ${max}`, path: ["size"] });
  }

  const [used, unused] =
    pagination === "cursor" ? ["after", "page"] : ["page", "after"];

  if (raw(unused) !== undefined) {
    issues.push({
      message: `This list pages with \`${used}\``,
      path: [unused],
    });
  }

  const page = read("page", 1);

  if (pagination === "offset" && page === undefined) {
    issues.push({ message: "Must be a positive integer", path: ["page"] });
  }

  const after = raw("after");

  if (
    pagination === "cursor" &&
    after !== undefined &&
    typeof after !== "string"
  ) {
    issues.push({ message: "Must be text", path: ["after"] });
  }

  if (issues.length > 0 || size === undefined) {
    return err(dbError("validation", "Invalid page parameters", { issues }));
  }

  return pagination === "cursor"
    ? ok({ after: typeof after === "string" ? after : null, size })
    : ok({ page: page ?? 1, size });
}

export function asObject(value: unknown): Result<unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? ok(value)
    : err(dbError("invalid_input", "Expected an object of column values"));
}

export function splitPath(
  subpath: string | readonly string[],
): Result<readonly string[]> {
  if (typeof subpath !== "string") {
    return ok(subpath);
  }

  try {
    return ok(
      subpath
        .split("/")
        .filter((segment) => segment !== "")
        .map((segment) => decodeURIComponent(segment)),
    );
  } catch {
    return err(dbError("invalid_input", `Malformed path ${subpath}`));
  }
}

export function contextOf(db: object): RequestContext {
  const value = "$context" in db ? db.$context : undefined;

  return isRecord(value) ? value : {};
}

/** Whether an action's path fits these segments, whatever the method. */
export function actionFits(
  action: PlannedAction<unknown>,
  segments: readonly string[],
): boolean {
  return (
    action.segments.length === segments.length &&
    action.segments.every((segment, index) =>
      segment.startsWith("{")
        ? segments[index] !== ""
        : segment === segments[index],
    )
  );
}
