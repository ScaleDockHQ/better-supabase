import type { Operation } from "../ir/types.ts";

import { compilePostgrest, type PostgrestPlan } from "../compile/postgrest.ts";

/**
 * Turns an IR operation into something a backend runs. An `Executor` for a
 * new backend usually pairs with a `Compiler` for it.
 */
export interface Compiler<TTarget> {
  readonly target: string;
  compile(op: Operation): TTarget;
}

export const postgrestCompiler: Compiler<PostgrestPlan> = {
  target: "postgrest",
  compile: compilePostgrest,
};
