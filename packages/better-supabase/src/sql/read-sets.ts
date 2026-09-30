import type { Executor } from "../core/executor.ts";
import type { ReadSet } from "../core/read-set.ts";
import type { Operation } from "../ir/types.ts";

import { compileSql, type SqlQuery } from "../compile/sql.ts";
import {
  hasPlaceholder,
  placeholderOf,
  splitPlaceholders,
} from "../core/read-set.ts";
import { ok } from "../core/result.ts";
import { sqlString } from "../core/template.ts";

/** A read set compiled to the SQL of its function. */
export interface CompiledReadSet {
  readonly name: string;
  readonly sql: string;
}

const TAG = "$rs$";

/** The operation each spec of the set runs, without plugins. */
async function operations(set: ReadSet): Promise<Map<string, Operation>> {
  const ops = new Map<string, Operation>();
  for (const [key, spec] of Object.entries(set.specs)) {
    const seen: Operation[] = [];
    const capture: Executor = {
      name: "read-set-compiler",
      execute: async (op) => {
        seen.push(op);
        return ok({ rows: [], count: 0 });
      },
    };
    // oxlint-disable-next-line anti-slop/no-chained-type-assertions -- the capture executor only records queries; repositories are indexed by name.
    const db = set.definition
      .connect(capture)
      .$withoutPlugins() as unknown as Record<
      string,
      Record<
        string,
        (
          ...args: unknown[]
        ) => PromiseLike<{ ok: boolean; error?: { message: string } }>
      >
    >;
    const method = db[spec.table]?.[spec.method];
    if (!method) {
      throw new TypeError(
        `Read set "${set.name}" entry "${key}": unknown table "${spec.table}"`,
      );
    }
    const result = await method(...spec.args);
    const [op, ...more] = seen;
    if (!op) {
      throw new TypeError(
        `Read set "${set.name}" entry "${key}": ${result.error?.message ?? "runs no query"}`,
      );
    }
    if (more.length > 0 || op.kind !== "select") {
      throw new TypeError(
        `Read set "${set.name}" entry "${key}": ${spec.method} needs more than one query; read sets take one select per entry`,
      );
    }
    ops.set(key, op);
  }
  return ops;
}

function paramRef(set: ReadSet, name: string, array: boolean): string {
  const type = set.params[name];
  if (!type)
    throw new TypeError(`Read set "${set.name}" has no parameter "${name}"`);
  if (array !== type.endsWith("[]")) {
    throw new TypeError(
      `Read set "${set.name}": parameter "${name}" (${type}) is used as ${array ? "a list" : "a single value"}`,
    );
  }
  const key = sqlString(name);
  return array
    ? `(array(select jsonb_array_elements_text(p->${key}))::${type})`
    : `((p->>${key})::${type})`;
}

function arrayElement(value: unknown): string {
  if (value === null || value === undefined) return "NULL";
  const text = value instanceof Date ? value.toISOString() : String(value);
  if (hasPlaceholder(text)) {
    throw new TypeError("A placeholder cannot sit inside a literal list");
  }
  return `"${text.replaceAll("\\", "\\\\").replaceAll('"', '\\"')}"`;
}

/** A parameter value as SQL: a reference to `p` for placeholders, else a literal. */
function literal(set: ReadSet, value: unknown): string {
  const placeholder = placeholderOf(value);
  if (placeholder) return paramRef(set, placeholder.name, placeholder.array);
  if (value === null || value === undefined) return "null";
  if (typeof value === "boolean") return value ? "true" : "false";
  if (typeof value === "number") {
    if (!Number.isFinite(value)) throw new TypeError(`Cannot inline ${value}`);
    return String(value);
  }
  if (typeof value === "bigint") return value.toString();
  if (value instanceof Date) return sqlString(value.toISOString());
  if (typeof value === "string") {
    if (!hasPlaceholder(value)) return sqlString(value);
    const parts = splitPlaceholders(value).map((part) =>
      "text" in part ? sqlString(part.text) : `(p->>${sqlString(part.param)})`,
    );
    return `(${parts.join(" || ")})`;
  }
  if (Array.isArray(value)) {
    return sqlString(`{${value.map(arrayElement).join(",")}}`);
  }
  throw new TypeError(`Cannot inline a ${typeof value} parameter`);
}

function inline(set: ReadSet, query: SqlQuery): string {
  return query.text.replace(/\$(\d+)/g, (_, index: string) =>
    literal(set, query.params[Number(index) - 1]),
  );
}

function entry(set: ReadSet, op: Operation): string {
  const plan = compileSql(op);
  if (plan.never) return `jsonb_build_object('rows', '[]'::jsonb, 'count', 0)`;
  const rows = plan.rows
    ? `(select coalesce(jsonb_agg(s.row), '[]'::jsonb) from (${inline(set, plan.rows)}) s)`
    : `'[]'::jsonb`;
  const count = plan.count ? `(${inline(set, plan.count)})` : "null";
  return `jsonb_build_object('rows', ${rows}, 'count', ${count})`;
}

/**
 * The function for a read set: `stable`, `security invoker` (RLS applies to
 * the caller) and with an empty `search_path`. Parameters are read from the
 * `p jsonb` argument; nothing is built dynamically.
 */
export async function compileReadSet(set: ReadSet): Promise<CompiledReadSet> {
  const ops = await operations(set);
  const entries = [...ops].map(
    ([key, op]) => `    ${sqlString(key)}, ${entry(set, op)}`,
  );
  const body = `  select jsonb_build_object(\n${entries.join(",\n")}\n  )`;
  if (body.includes(TAG)) {
    throw new TypeError(`Read set "${set.name}" contains "${TAG}"`);
  }
  // defineReadSet only accepts snake_case names, so no quoting is needed.
  const fn = `public.${set.functionName}`;
  const grants = set.roles.map(
    (role) => `grant execute on function ${fn}(jsonb) to ${role};`,
  );
  const sql = [
    `create or replace function ${fn}(p jsonb)`,
    "  returns jsonb",
    "  language sql stable security invoker set search_path = ''",
    `as ${TAG}`,
    body,
    `${TAG};`,
    `revoke execute on function ${fn}(jsonb) from public, anon, authenticated;`,
    ...grants,
  ].join("\n");
  return { name: set.name, sql };
}

/** Compiles every set, sorted by name. Throws on a duplicate name. */
export async function compileReadSets(
  sets: readonly ReadSet[],
): Promise<CompiledReadSet[]> {
  const byName = new Map<string, ReadSet>();
  for (const set of sets) {
    const existing = byName.get(set.name);
    if (existing && existing !== set) {
      throw new TypeError(`Two read sets are named "${set.name}"`);
    }
    byName.set(set.name, set);
  }
  const names = [...byName.keys()].sort();
  return Promise.all(names.map((name) => compileReadSet(byName.get(name)!)));
}
