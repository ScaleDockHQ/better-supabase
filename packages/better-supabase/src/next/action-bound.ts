import type { DbError } from "../core/errors.ts";
import type { Result } from "../core/result.ts";
import type { StandardSchemaV1 } from "../core/standard.ts";
import type { CachedOptions } from "./types.ts";

import { methodOf } from "../blocks/block-method.ts";
import { readSetTables } from "../core/read-set.ts";
import { validate } from "../core/standard.ts";
import { tableTags } from "./cache.ts";

/**
 * The validated bound arguments of an action, or the arguments as they are
 * without a schema.
 */
export async function validateBound(
  schema: StandardSchemaV1<readonly unknown[]> | undefined,
  args: readonly unknown[],
): Promise<
  | { readonly ok: true; readonly data: unknown }
  | { readonly ok: false; readonly error: DbError }
> {
  if (!schema) {
    return { ok: true, data: args };
  }

  const checked = await validate(schema, args, "bound");

  return checked.ok
    ? { ok: true, data: checked.data }
    : { ok: false, error: checked.error };
}

/** `entry` with the tables of its read set added to `tables`. */
export function withReadSetTables(entry: CachedOptions): CachedOptions {
  return entry.readSet
    ? {
        ...entry,
        tables: [...(entry.tables ?? []), ...readSetTables(entry.readSet)],
      }
    : entry;
}

/**
 * The server action behind `bsb.blockAction`: calls one block method as the
 * caller and drops the tags of `invalidates` after a success.
 */
export function blockActionOf(
  host: {
    readonly action: (
      options: never,
      fn: (input: never, ctx: never) => Promise<Result<unknown>>,
    ) => unknown;
  },
  invalidate: (tags: readonly string[]) => void,
  client: (ctx: never) => object,
  method: string,
  options: {
    readonly args?: (input: never, ctx: never) => unknown;
    readonly invalidates?: readonly string[];
  },
): never {
  // SAFETY: the options are the action options `blockAction` was given.
  const run = host.action(options as never, async (input, ctx) => {
    const call = methodOf(client(ctx), method);

    // SAFETY: BlockActionParams makes `args` required unless the method
    // takes the validated input as its only argument.
    const args = (options.args?.(input, ctx) ?? [input]) as readonly unknown[];

    const result = await call(...args);

    if (result.ok && options.invalidates) {
      invalidate(
        options.invalidates.flatMap((table) =>
          tableTags(table, { tenant: "*" }),
        ),
      );
    }

    return result;
  });

  // SAFETY: the method's `Result` carries `BlockDataOf<Cl, K>`.
  return run as never;
}
