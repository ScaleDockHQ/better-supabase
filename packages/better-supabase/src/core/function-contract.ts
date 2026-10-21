import type { StandardSchemaV1 } from "./standard.ts";

/** What a typed Edge Function takes and returns, as the caller sees them. */
export interface FunctionContract<In = unknown, Out = unknown> {
  readonly input: In;
  readonly output: Out;
}

/**
 * The key `defineFunction` stores its schemas under, so `better-supabase/spec`
 * can read them without importing `edge`.
 */
export const FUNCTION_DESCRIPTOR: unique symbol = Symbol.for(
  "better-supabase.function",
);

/**
 * The schemas and docs of a `defineFunction` handler, kept on the handler for
 * spec generation.
 */
export interface FunctionDescriptor {
  readonly input: StandardSchemaV1;
  readonly output?: StandardSchemaV1;
  readonly summary?: string;
}

/** A handler that carries a `FunctionDescriptor`. */
export interface DescribedFunction {
  readonly [FUNCTION_DESCRIPTOR]: FunctionDescriptor;
}
