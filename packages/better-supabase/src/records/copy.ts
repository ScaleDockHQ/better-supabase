import type { Result } from "../core/result.ts";
import type { RecordRef } from "../schema/types.ts";
import type { BindingBlocks } from "./bindings.ts";

import { dbError } from "../core/errors.ts";
import { err, ok } from "../core/result.ts";
import { findBinding } from "./bindings.ts";

/** The bindings of `blocks` that can copy their rows. */
export function copyableBindings(blocks: BindingBlocks): readonly string[] {
  return Object.keys(blocks).filter(
    (name) => findBinding(blocks, name)?.binding.copy !== undefined,
  );
}

/**
 * Copies the rows of the named bindings from one record to another, one binding
 * after the other, and returns how many rows each copied. It stops at the first
 * binding that fails and returns its error. Without `bindings` every binding
 * that has a `copy` runs.
 *
 * ```ts
 * const copied = await copyBindings(
 *   { blocks: blockSet.blocks, clients: blocks },
 *   { type: "customer", id: from },
 *   { type: "customer", id: to },
 * );
 * ```
 */
export async function copyBindings(
  source: { readonly blocks: BindingBlocks; readonly clients: object },
  from: RecordRef,
  to: RecordRef,
  bindings: readonly string[] = copyableBindings(source.blocks),
): Promise<Result<Readonly<Record<string, number>>>> {
  const counts: Record<string, number> = {};

  for (const name of bindings) {
    const found = findBinding(source.blocks, name);

    // SAFETY: a read of one key of the built blocks.
    const client = (source.clients as Readonly<Record<string, unknown>>)[name];

    if (found?.binding.copy === undefined || client === undefined) {
      return err(
        dbError(
          "invalid_request",
          `Record binding "${name}" can't copy its rows`,
        ),
      );
    }

    // SAFETY: the copy takes the client its block's creator made.
    const copied = await found.binding.copy(client as never, from, to);

    if (!copied.ok) {
      return copied;
    }

    counts[name] = copied.data;
  }

  return ok(counts);
}
