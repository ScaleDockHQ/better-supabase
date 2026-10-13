import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";

import { dbError } from "../../core/errors.ts";
import { AsyncResult, ok } from "../../core/result.ts";
import { blockCall, isRecord } from "../shared.ts";

/** One call that reverses part of a change. */
export interface UndoCall {
  readonly fn: string;
  readonly args: Readonly<Record<string, unknown>>;
}

/**
 * What a block method returns when its change has an inverse. It is plain
 * JSON, so it can travel from a server action to a toast and back. Applying
 * it runs the calls in order as the caller, so the same permission checks
 * apply as for any other write.
 */
export interface UndoToken {
  readonly v: 1;
  readonly calls: readonly UndoCall[];
}

/** The functions an undo token may call: the inverses the blocks return. */
export const UNDO_FUNCTIONS: readonly string[] = [
  "link",
  "unlink",
  "revert_audit_entries",
];

export function undoToken(calls: readonly UndoCall[]): UndoToken {
  return { v: 1, calls };
}

/** Whether a value is an undo token whose calls are all allowed. */
export function isUndoToken(
  value: unknown,
  allowed: readonly string[] = UNDO_FUNCTIONS,
): value is UndoToken {
  return (
    isRecord(value) &&
    value["v"] === 1 &&
    Array.isArray(value["calls"]) &&
    value["calls"].length > 0 &&
    value["calls"].every(
      (call: unknown) =>
        isRecord(call) &&
        typeof call["fn"] === "string" &&
        allowed.includes(call["fn"]) &&
        isRecord(call["args"]),
    )
  );
}

export interface UndoOptions {
  readonly transport: BlockTransport;
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /** Extra functions a token may call, for an app's own inverses. */
  readonly allow?: readonly string[];
}

export interface Undo {
  /** Runs a token's calls in order; stops at the first error. */
  apply(token: unknown): AsyncResult<number>;
}

export function createUndo(options: UndoOptions): Undo {
  const call = blockCall(options.transport, options.schema, options.mappers);
  const allowed = [...UNDO_FUNCTIONS, ...(options.allow ?? [])];
  return {
    apply: (token) => {
      if (!isUndoToken(token, allowed)) {
        return AsyncResult.err(
          dbError("validation", "not an undo token this app accepts", {
            issues: [
              { message: "not an undo token this app accepts", path: [] },
            ],
          }),
        );
      }
      return AsyncResult.from(async () => {
        for (const step of token.calls) {
          const result = await call(step.fn, step.args, () => undefined);
          if (!result.ok) return result;
        }
        return ok(token.calls.length);
      });
    },
  };
}
