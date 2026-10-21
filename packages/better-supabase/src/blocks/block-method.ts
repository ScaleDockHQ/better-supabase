import type { Result } from "../core/result.ts";

type AnyMethod = (...args: never[]) => PromiseLike<Result<unknown>>;

/** The method names of a block client. */
export type BlockMethodName<C> = {
  readonly [K in keyof C]: C[K] extends AnyMethod ? K : never;
}[keyof C] &
  string;

/** The arguments of a block client method. */
export type BlockArgsOf<C, K extends BlockMethodName<C>> = C[K] extends (
  ...args: infer A
) => PromiseLike<Result<unknown>>
  ? A
  : never;

/**
 * What one call of a block method takes as a single value: its argument, or the
 * tuple of its arguments when it has more than one.
 */
export type BlockInputOf<C, K extends BlockMethodName<C>> = BlockArgsOf<
  C,
  K
>["length"] extends 0 | 1
  ? BlockArgsOf<C, K>[0]
  : BlockArgsOf<C, K>;

/**
 * Calls `method` with `input` as one value: an array is spread when the method
 * takes more than one argument, as `BlockInputOf` describes.
 */
export function callWithInput(
  client: object,
  method: string,
  input: unknown,
): PromiseLike<Result<unknown>> {
  const call = methodOf(client, method);

  if (call.length > 1 && Array.isArray(input)) {
    const args: readonly unknown[] = input;

    return call(...args);
  }

  return call(input);
}

/** The data a block client method's `Result` carries. */
export type BlockDataOf<C, K extends BlockMethodName<C>> = C[K] extends (
  ...args: never[]
) => PromiseLike<infer R>
  ? R extends { readonly ok: true; readonly data: infer D }
    ? D
    : never
  : never;

/**
 * The bound method `method` of a block client. Throws a `TypeError` when the
 * client has no such method.
 */
export function methodOf(
  client: object,
  method: string,
): (...args: unknown[]) => PromiseLike<Result<unknown>> {
  // SAFETY: a read of the method name `BlockMethodName` took from the client.
  const value = (client as Readonly<Record<string, unknown>>)[method];

  if (typeof value !== "function") {
    throw new TypeError(`better-supabase: the block client has no ${method}`);
  }

  // SAFETY: block client methods return an `AsyncResult`, a
  // `PromiseLike<Result>`.
  return value.bind(client) as (
    ...args: unknown[]
  ) => PromiseLike<Result<unknown>>;
}
