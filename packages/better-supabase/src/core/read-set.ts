import type { AnyFunctions, AnyModels, SchemaMeta } from "../schema/types.ts";
import type { BetterSupabase } from "./define.ts";
import type { AnyPlugin } from "./plugin.ts";
import type { InferResult, QuerySpec, Specs } from "./spec.ts";

import { type DbError, dbError } from "./errors.ts";
import { isQuerySpec, specTables } from "./spec.ts";

type ScalarParamType =
  | "uuid"
  | "text"
  | "bool"
  | "int2"
  | "int4"
  | "int8"
  | "float4"
  | "float8"
  | "numeric"
  | "date"
  | "timestamp"
  | "timestamptz";

/**
 * The Postgres type of a read-set parameter. `[]` types take an array. Name
 * enums and domains with their schema (`public.note_kind`): the function
 * runs with an empty `search_path`.
 */
export type ReadSetParamType =
  | ScalarParamType
  | `${ScalarParamType}[]`
  | `${string}.${string}`;

export type ReadSetParamTypes = Readonly<Record<string, ReadSetParamType>>;

type ScalarValue<T> = T extends
  | "int2"
  | "int4"
  | "int8"
  | "float4"
  | "float8"
  | "numeric"
  ? number
  : T extends "bool"
    ? boolean
    : string;

/** The value a parameter of type `T` takes. */
export type ReadSetParamValue<T> = T extends `${infer E}[]`
  ? readonly ScalarValue<E>[]
  : ScalarValue<T>;

export type ReadSetParams<P extends ReadSetParamTypes> = {
  readonly [K in keyof P]: ReadSetParamValue<P[K]>;
};

/**
 * Placeholders for the caller's identity, the third argument of a read
 * set's builder. The function reads them in the database, so callers can't
 * pass someone else's.
 */
export interface ReadSetAuth {
  /** The caller's user id: `auth.uid()` in the function, the JWT `sub` claim otherwise. */
  readonly uid: string;
}

type ReadSetRole = "anon" | "authenticated";

/**
 * Named reads that run together: one `stable` function over PostgREST (a
 * single GET), one transaction over SQL. Build it with `defineReadSet`, run
 * it with `db.$many(readSet, params)`.
 */
export interface ReadSet<
  N extends string = string,
  P extends ReadSetParamTypes = ReadSetParamTypes,
  S extends Readonly<Record<string, QuerySpec>> = Readonly<
    Record<string, QuerySpec>
  >,
> {
  readonly kind: "read-set";
  readonly name: N;
  /** The database function `better-supabase gen` writes for this set. */
  readonly functionName: `rs_${N}`;
  readonly params: P;
  /** Roles granted execute on the function. */
  readonly roles: readonly ReadSetRole[];
  /** The reads, with placeholders where parameters go. */
  readonly specs: S;
  readonly definition: BetterSupabase;
}

/** What `db.$many(readSet, params)` resolves to. */
export type ReadSetResult<S> =
  S extends ReadSet<string, ReadSetParamTypes, infer Q>
    ? { readonly [K in keyof Q]: InferResult<Q[K]> }
    : never;

/** The parameters `db.$many(readSet, params)` takes. */
export type InferReadSetParams<S> =
  S extends ReadSet<string, infer P> ? ReadSetParams<P> : never;

export interface ReadSetOptions<P extends ReadSetParamTypes> {
  readonly params?: P;
  /** Roles that may call the function. Defaults to `['authenticated']`. */
  readonly roles?: readonly ReadSetRole[];
}

const NAME = /^[a-z][a-z0-9_]{0,59}$/;
const PARAM = /^[a-z_][a-z0-9_]*$/i;
const TYPE = /^(?:[a-z_][a-z0-9_]*\.)?[a-z_][a-z0-9_]*(?:\[\])?$/;
/** `jsonb_build_object` takes at most 100 arguments. */
const MAX_ENTRIES = 50;
/**
 * Placeholders are `NUL bs:<name> NUL`: no real parameter value holds a NUL.
 * Auth placeholders start with `@`, which no parameter name can.
 */
const NUL = "\u0000";
const SENTINEL = new RegExp(`${NUL}bs:(@?[a-z_][a-z0-9_]*)${NUL}`, "gi");
const EXACT = new RegExp(`^${NUL}bs:(@?[a-z_][a-z0-9_]*)${NUL}$`, "i");

function sentinel(name: string): string {
  return `${NUL}bs:${name}${NUL}`;
}

const AUTH: ReadSetAuth = { uid: sentinel("@uid") };

/** What a placeholder stands for: a caller parameter or the caller's identity. */
export type Placeholder =
  | { readonly kind: "param"; readonly name: string; readonly array: boolean }
  | { readonly kind: "auth"; readonly name: "uid"; readonly array: boolean };

function tagged(name: string, array: boolean): Placeholder | undefined {
  if (!name.startsWith("@")) return { kind: "param", name, array };
  return name === "@uid" ? { kind: "auth", name: "uid", array } : undefined;
}

/**
 * Registers reads that run as one round trip:
 *
 * ```ts
 * export const appChrome = defineReadSet(
 *   betterSupabase,
 *   'app_chrome',
 *   { params: { userId: 'uuid' } },
 *   (s, p) => ({
 *     unread: s.notifications.count({ where: { userId: p.userId, readAt: null } }),
 *     me: s.profiles.findFirst({ where: { id: p.userId } }),
 *   }),
 * );
 * ```
 *
 * `p` holds placeholders, not values: pass them straight into `where` (or
 * `in`), where the function reads them from its `p jsonb` argument.
 */
export function defineReadSet<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  const N extends string,
  const P extends ReadSetParamTypes,
  const S extends Readonly<Record<string, QuerySpec>>,
>(
  betterSupabase: BetterSupabase<M, D, F, E>,
  name: N,
  options: ReadSetOptions<P>,
  build: (specs: Specs<M, E>, params: ReadSetParams<P>, auth: ReadSetAuth) => S,
): ReadSet<N, P, S> {
  if (!NAME.test(name)) {
    throw new TypeError(
      `better-supabase: read set name "${name}" must be snake_case and at most 60 characters`,
    );
  }
  // SAFETY: params defaults to no parameters, which every P accepts.
  const params = (options.params ?? {}) as P;
  const placeholders: Record<string, unknown> = {};
  for (const [key, type] of Object.entries(params)) {
    if (!PARAM.test(key)) {
      throw new TypeError(
        `better-supabase: read set "${name}" has an invalid parameter name "${key}"`,
      );
    }
    if (!TYPE.test(type)) {
      throw new TypeError(
        `better-supabase: read set "${name}" parameter "${key}" has an invalid type "${type}"`,
      );
    }
    placeholders[key] = type.endsWith("[]") ? [sentinel(key)] : sentinel(key);
  }
  // SAFETY: the loop above filled a placeholder for every parameter in P.
  const specs = build(
    betterSupabase.spec,
    placeholders as ReadSetParams<P>,
    AUTH,
  );
  const entries = Object.entries(specs);
  if (entries.length === 0 || entries.length > MAX_ENTRIES) {
    throw new TypeError(
      `better-supabase: read set "${name}" needs between 1 and ${MAX_ENTRIES} reads`,
    );
  }
  for (const [key, spec] of entries) {
    if (!isQuerySpec(spec)) {
      throw new TypeError(
        `better-supabase: read set "${name}" entry "${key}" is not a spec from betterSupabase.spec`,
      );
    }
  }
  warnUnscopedReads(betterSupabase, name, specs);
  return {
    kind: "read-set",
    name,
    functionName: `rs_${name}`,
    params,
    roles: options.roles ?? ["authenticated"],
    specs,
    // SAFETY: the read set stores the definition without its schema generics.
    // oxlint-disable-next-line anti-slop/no-chained-type-assertions -- the read set stores the definition without its schema generics.
    definition: betterSupabase as unknown as ReadSet["definition"],
  };
}

/**
 * The generated function runs the reads as compiled at `gen` time, without
 * the runtime's `transformQuery` plugins, so tenant and soft-delete filters
 * that only those plugins add never reach it.
 */
function warnUnscopedReads(
  betterSupabase: Pick<BetterSupabase, "plugins" | "events" | "meta">,
  name: string,
  specs: Readonly<Record<string, QuerySpec>>,
): void {
  const filtering = betterSupabase.plugins.filter(
    (plugin) =>
      plugin.transformQuery !== undefined && plugin.scopes?.length !== 0,
  );
  if (filtering.length === 0) return;
  const { meta } = betterSupabase;
  const filters = (plugin: AnyPlugin, key: string): boolean => {
    const flags = meta.tables[key]?.flags;
    return (
      plugin.scopes === undefined ||
      plugin.scopes.some((flag) => flags?.[flag] !== undefined)
    );
  };
  const read = [
    ...new Set(Object.values(specs).flatMap((spec) => specTables(meta, spec))),
  ];
  const tables = read.filter((key) =>
    filtering.some((plugin) => filters(plugin, key)),
  );
  if (tables.length === 0) return;
  const scoping = filtering
    .filter((plugin) => tables.some((key) => filters(plugin, key)))
    .map((plugin) => plugin.name);
  betterSupabase.events.logger.warn(
    `read set "${name}" reads ${tables.join(", ")}, which ${scoping.join(", ")} scope at runtime; its generated function only sees those filters when the specs spell them out (or RLS enforces them)`,
    { readSet: name, tables, plugins: scoping },
  );
}

export function isReadSet(value: unknown): value is ReadSet {
  // SAFETY: value is a non-null object here, and each property read is type-checked.
  return (
    typeof value === "object" &&
    value !== null &&
    (value as Partial<ReadSet>).kind === "read-set" &&
    typeof (value as Partial<ReadSet>).name === "string"
  );
}

/** The placeholder a string or array carries, if it is exactly one. */
export function placeholderOf(value: unknown): Placeholder | undefined {
  if (typeof value === "string") {
    const match = EXACT.exec(value);
    return match ? tagged(match[1]!, false) : undefined;
  }
  if (Array.isArray(value) && value.length === 1) {
    const inner = placeholderOf(value[0]);
    return inner && !inner.array ? { ...inner, array: true } : inner;
  }
  return undefined;
}

/** Splits a string around the placeholders inside it. */
export function splitPlaceholders(
  value: string,
): readonly ({ readonly text: string } | Placeholder)[] {
  const parts: ({ text: string } | Placeholder)[] = [];
  let last = 0;
  for (const match of value.matchAll(SENTINEL)) {
    if (match.index > last)
      parts.push({ text: value.slice(last, match.index) });
    const placeholder = tagged(match[1]!, false);
    parts.push(placeholder ?? { text: match[0] });
    last = match.index + match[0].length;
  }
  if (last < value.length) parts.push({ text: value.slice(last) });
  return parts;
}

export function hasPlaceholder(value: string): boolean {
  return value.includes(`${NUL}bs:`);
}

/** Whether any string inside `value` is (or holds) a placeholder. */
export function containsPlaceholder(value: unknown): boolean {
  if (typeof value === "string") return hasPlaceholder(value);
  if (Array.isArray(value)) return value.some(containsPlaceholder);
  if (typeof value === "object" && value !== null) {
    return Object.values(value).some(containsPlaceholder);
  }
  return false;
}

/** Whether the set's specs read the caller's identity. */
function readSetUsesAuth(set: ReadSet): boolean {
  return Object.values(set.specs).some((spec) => usesAuth(spec.args));
}

function usesAuth(value: unknown): boolean {
  if (typeof value === "string") {
    return [...value.matchAll(SENTINEL)].some((match) =>
      match[1]!.startsWith("@"),
    );
  }
  if (Array.isArray(value)) return value.some(usesAuth);
  if (typeof value === "object" && value !== null) {
    return Object.values(value).some(usesAuth);
  }
  return false;
}

/** Missing or wrongly typed parameters, as messages. */
export function checkParams(
  set: ReadSet,
  values: Readonly<Record<string, unknown>> | undefined,
): string[] {
  const problems: string[] = [];
  for (const [key, type] of Object.entries(set.params)) {
    const value = values?.[key];
    if (value === undefined || value === null) {
      problems.push(`missing parameter "${key}"`);
    } else if (type.endsWith("[]") !== Array.isArray(value)) {
      problems.push(
        `parameter "${key}" must be ${type.endsWith("[]") ? "an array" : "a single value"}`,
      );
    }
  }
  return problems;
}

/**
 * The specs with every placeholder replaced by its value; `auth.uid` takes
 * the `sub` claim, which must be verified. `noCaller` is set when the set
 * reads `auth.uid` and there is no `sub`: the specs then match no user, and
 * only the function, which reads `auth.uid()` itself, can run the set.
 */
export function bindParams(
  set: ReadSet,
  values: Readonly<Record<string, unknown>> | undefined,
  context: { readonly claims?: Readonly<Record<string, unknown>> },
): {
  readonly specs: Readonly<Record<string, QuerySpec>>;
  readonly noCaller: DbError | undefined;
} {
  const sub = context.claims?.["sub"];
  const uid = typeof sub === "string" && sub !== "" ? sub : null;
  const valueOf = (placeholder: Placeholder): unknown =>
    placeholder.kind === "auth" ? uid : values?.[placeholder.name];
  const bind = (value: unknown): unknown => {
    const placeholder = placeholderOf(value);
    if (placeholder) {
      const bound = valueOf(placeholder);
      return placeholder.kind === "auth" && placeholder.array ? [bound] : bound;
    }
    if (typeof value === "string") {
      if (!hasPlaceholder(value)) return value;
      return splitPlaceholders(value)
        .map((part) =>
          "text" in part ? part.text : String(valueOf(part) ?? ""),
        )
        .join("");
    }
    if (Array.isArray(value)) return value.map(bind);
    if (typeof value === "object" && value !== null) {
      if (Object.getPrototypeOf(value) !== Object.prototype) return value;
      return Object.fromEntries(
        Object.entries(value).map(([key, entry]) => [key, bind(entry)]),
      );
    }
    return value;
  };
  const specs = Object.fromEntries(
    Object.entries(set.specs).map(([key, spec]) => [
      key,
      { ...spec, args: spec.args.map(bind) },
    ]),
  );
  const noCaller =
    uid === null && readSetUsesAuth(set)
      ? dbError(
          "invalid_request",
          `db.$many(${set.name}): the read set reads auth.uid, but this connection has no user claims. Connect with the user's verified claims ({ claims: { sub } }), or call it over PostgREST, where the function reads auth.uid().`,
        )
      : undefined;
  return { specs, noCaller };
}

/** App keys of every table the set reads. */
export function readSetTables(set: ReadSet, meta?: SchemaMeta): string[] {
  const schema = meta ?? set.definition.meta;
  return [
    ...new Set(
      Object.values(set.specs).flatMap((spec) => specTables(schema, spec)),
    ),
  ];
}
