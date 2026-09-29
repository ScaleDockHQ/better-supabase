import type { AnyFunctions, AnyModels, SchemaMeta } from '../schema/types.ts';
import type { BetterSupabase } from './define.ts';
import type { InferResult, QuerySpec, Specs } from './spec.ts';

import { isQuerySpec, specTables } from './spec.ts';

type ScalarParamType =
  | 'uuid'
  | 'text'
  | 'bool'
  | 'int2'
  | 'int4'
  | 'int8'
  | 'float4'
  | 'float8'
  | 'numeric'
  | 'date'
  | 'timestamp'
  | 'timestamptz';

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
  | 'int2'
  | 'int4'
  | 'int8'
  | 'float4'
  | 'float8'
  | 'numeric'
  ? number
  : T extends 'bool'
    ? boolean
    : string;

/** The value a parameter of type `T` takes. */
export type ReadSetParamValue<T> = T extends `${infer E}[]`
  ? readonly ScalarValue<E>[]
  : ScalarValue<T>;

export type ReadSetParams<P extends ReadSetParamTypes> = {
  readonly [K in keyof P]: ReadSetParamValue<P[K]>;
};

type ReadSetRole = 'anon' | 'authenticated';

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
  readonly kind: 'read-set';
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
/** Placeholders are `NUL bs:<name> NUL`: no real parameter value holds a NUL. */
const NUL = String.fromCharCode(0);
const SENTINEL = new RegExp(`${NUL}bs:([a-z_][a-z0-9_]*)${NUL}`, 'gi');
const EXACT = new RegExp(`^${NUL}bs:([a-z_][a-z0-9_]*)${NUL}$`, 'i');

function sentinel(name: string): string {
  return `${NUL}bs:${name}${NUL}`;
}

/**
 * Registers reads that run as one round trip:
 *
 * ```ts
 * export const appChrome = defineReadSet(
 *   sb,
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
  sb: BetterSupabase<M, D, F, E>,
  name: N,
  options: ReadSetOptions<P>,
  build: (specs: Specs<M, E>, params: ReadSetParams<P>) => S,
): ReadSet<N, P, S> {
  if (!NAME.test(name)) {
    throw new TypeError(
      `better-supabase: read set name "${name}" must be snake_case and at most 60 characters`,
    );
  }
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
    placeholders[key] = type.endsWith('[]') ? [sentinel(key)] : sentinel(key);
  }
  const specs = build(sb.spec, placeholders as ReadSetParams<P>);
  const entries = Object.entries(specs);
  if (entries.length === 0 || entries.length > MAX_ENTRIES) {
    throw new TypeError(
      `better-supabase: read set "${name}" needs between 1 and ${MAX_ENTRIES} reads`,
    );
  }
  for (const [key, spec] of entries) {
    if (!isQuerySpec(spec)) {
      throw new TypeError(
        `better-supabase: read set "${name}" entry "${key}" is not a spec from sb.spec`,
      );
    }
  }
  return {
    kind: 'read-set',
    name,
    functionName: `rs_${name}`,
    params,
    roles: options.roles ?? ['authenticated'],
    specs,
    // oxlint-disable-next-line anti-slop/no-chained-type-assertions -- the read set stores the definition without its schema generics.
    definition: sb as unknown as ReadSet['definition'],
  };
}

export function isReadSet(value: unknown): value is ReadSet {
  return (
    typeof value === 'object' &&
    value !== null &&
    (value as Partial<ReadSet>).kind === 'read-set' &&
    typeof (value as Partial<ReadSet>).name === 'string'
  );
}

/** A parameter a string or array carries, if it is exactly a placeholder. */
export function placeholderOf(
  value: unknown,
): { readonly name: string; readonly array: boolean } | undefined {
  if (typeof value === 'string') {
    const match = EXACT.exec(value);
    return match ? { name: match[1]!, array: false } : undefined;
  }
  if (Array.isArray(value) && value.length === 1) {
    const inner = placeholderOf(value[0]);
    return inner && !inner.array ? { name: inner.name, array: true } : inner;
  }
  return undefined;
}

/** Splits a string around the placeholders inside it. */
export function splitPlaceholders(
  value: string,
): readonly ({ readonly text: string } | { readonly param: string })[] {
  const parts: ({ text: string } | { param: string })[] = [];
  let last = 0;
  for (const match of value.matchAll(SENTINEL)) {
    if (match.index > last)
      parts.push({ text: value.slice(last, match.index) });
    parts.push({ param: match[1]! });
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
  if (typeof value === 'string') return hasPlaceholder(value);
  if (Array.isArray(value)) return value.some(containsPlaceholder);
  if (typeof value === 'object' && value !== null) {
    return Object.values(value).some(containsPlaceholder);
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
    } else if (type.endsWith('[]') !== Array.isArray(value)) {
      problems.push(
        `parameter "${key}" must be ${type.endsWith('[]') ? 'an array' : 'a single value'}`,
      );
    }
  }
  return problems;
}

/** The specs with every placeholder replaced by its value. */
export function bindParams(
  set: ReadSet,
  values: Readonly<Record<string, unknown>>,
): Readonly<Record<string, QuerySpec>> {
  const bind = (value: unknown): unknown => {
    const placeholder = placeholderOf(value);
    if (placeholder) return values[placeholder.name];
    if (typeof value === 'string') {
      if (!hasPlaceholder(value)) return value;
      return splitPlaceholders(value)
        .map((part) =>
          'text' in part ? part.text : String(values[part.param] ?? ''),
        )
        .join('');
    }
    if (Array.isArray(value)) return value.map(bind);
    if (typeof value === 'object' && value !== null) {
      if (Object.getPrototypeOf(value) !== Object.prototype) return value;
      return Object.fromEntries(
        Object.entries(value).map(([key, entry]) => [key, bind(entry)]),
      );
    }
    return value;
  };
  return Object.fromEntries(
    Object.entries(set.specs).map(([key, spec]) => [
      key,
      { ...spec, args: spec.args.map(bind) },
    ]),
  );
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
