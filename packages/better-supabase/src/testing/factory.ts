import type { StoragePath } from "../storage/path.ts";

import { temporal } from "../core/temporal-required.ts";

/**
 * A foreign key value, or the parent row it points at: the factory reads the
 * referenced column from a row.
 */
export type FactoryRef<V> = V | Readonly<Record<string, unknown>>;

/**
 * What a factory call takes: any insert column, with foreign keys (`F`) also
 * taking the parent row. The columns in `R` have no default, so a call needs
 * them.
 */
export type FactoryInput<
  I,
  F extends keyof I = never,
  R extends keyof I = never,
> = { readonly [K in Exclude<keyof I, F | R>]?: I[K] } & {
  readonly [K in Exclude<F, R>]?: FactoryRef<I[K]>;
} & { readonly [K in Exclude<R, F>]-?: Exclude<I[K], undefined> } & {
  readonly [K in R & F]-?: FactoryRef<Exclude<I[K], undefined>>;
};

type FactoryArgs<I, F extends keyof I, R extends keyof I> = [R] extends [never]
  ? [input?: FactoryInput<I, F, R>]
  : [input: FactoryInput<I, F, R>];

/** Anything with a repository's `create`, such as `db.customers`. */
export interface FactoryTarget<I, T> {
  create(data: I): T;
}

/** Builds valid insert rows for one table. */
export interface Factory<
  I,
  F extends keyof I = never,
  R extends keyof I = never,
> {
  /** One row: the defaults for call `n`, then `input`. */
  (...args: FactoryArgs<I, F, R>): I;
  /** `count` rows, each with its own defaults. */
  many(count: number, ...args: FactoryArgs<I, F, R>): I[];
  /** Builds one row and passes it to `repository.create`. */
  create<T>(repository: FactoryTarget<I, T>, ...args: FactoryArgs<I, F, R>): T;
}

function isRow(value: unknown): value is Readonly<Record<string, unknown>> {
  return (
    typeof value === "object" &&
    value !== null &&
    !Array.isArray(value) &&
    Object.getPrototypeOf(value) === Object.prototype
  );
}

/**
 * A factory from the defaults of call `n` and the foreign keys it resolves,
 * each mapped to the column it references in the parent row. `factories()`
 * generates one per table:
 *
 * ```ts
 * const tasks = defineFactory<
 *   InsertOf<"tasks">,
 *   "customerId",
 *   "customerId"
 * >((n) => ({ title: `title ${n}` }), { customerId: "id" });
 * tasks({ customerId: acme });
 * ```
 */
export function defineFactory<
  I,
  F extends keyof I & string = never,
  R extends keyof I = never,
>(
  defaults: (n: number) => Partial<I>,
  refs: { readonly [K in F]: string },
): Factory<I, F, R> {
  const columns: Readonly<Record<string, string>> = refs;
  let calls = 0;

  const build = (input: object = {}): I => {
    calls += 1;

    const row: Record<string, unknown> = { ...defaults(calls) };

    for (const [key, value] of Object.entries(input)) {
      const column = columns[key];

      row[key] = column !== undefined && isRow(value) ? value[column] : value;
    }

    // SAFETY: the defaults fill every required column the generator saw and
    // the input types the rest, so the row is a valid insert.
    return row as I;
  };

  const factory = (...args: FactoryArgs<I, F, R>): I => build(args[0]);

  return Object.assign(factory, {
    many: (count: number, ...args: FactoryArgs<I, F, R>): I[] =>
      Array.from({ length: count }, () => build(args[0])),
    create: <T>(
      repository: FactoryTarget<I, T>,
      ...args: FactoryArgs<I, F, R>
    ): T => repository.create(build(args[0])),
  });
}

/** A storage path in bucket `B` for a factory default. */
export function factoryPath<B extends string>(
  _bucket: B,
  path: string,
): StoragePath<B> {
  // SAFETY: a test path names an object in `bucket`; nothing reads the brand.
  return path as StoragePath<B>;
}

/**
 * The fixed times the generated factories use (2026-01-01), read through the
 * Temporal the app provides.
 */
export const factoryTime: {
  readonly instant: () => Temporal.Instant;
  readonly plainDate: () => Temporal.PlainDate;
  readonly plainDateTime: () => Temporal.PlainDateTime;
  readonly plainTime: () => Temporal.PlainTime;
} = {
  instant: () => temporal().Instant.from("2026-01-01T00:00:00Z"),
  plainDate: () => temporal().PlainDate.from("2026-01-01"),
  plainDateTime: () => temporal().PlainDateTime.from("2026-01-01T00:00:00"),
  plainTime: () => temporal().PlainTime.from("00:00:00"),
};
