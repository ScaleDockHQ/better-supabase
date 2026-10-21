import type { EdgeHandler } from "../bridges/edge.ts";
import type {
  DescribedFunction,
  FunctionContract,
  FunctionDescriptor,
} from "../core/function-contract.ts";
import type { Result } from "../core/result.ts";
import type { StandardSchemaV1 } from "../core/standard.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";
import type { MiddlewareOptions } from "../server/respond.ts";
import type { ServerContext } from "../server/server-types.ts";
import type { BetterEdge } from "./index.ts";

import { dbError } from "../core/errors.ts";
import { FUNCTION_DESCRIPTOR } from "../core/function-contract.ts";
import { err, ok } from "../core/result.ts";
import { validate } from "../core/standard.ts";
import { withExtra } from "../server/extra.ts";
import { settle } from "../server/respond.ts";

export type { FunctionContract };

/**
 * A fetch handler that carries its contract in its type and its schemas at
 * runtime.
 */
export type TypedFunction<In, Out> = EdgeHandler &
  DescribedFunction & {
    /** Type-only: never set at runtime. */
    readonly "~contract"?: FunctionContract<In, Out>;
  };

/**
 * The contract of a `defineFunction` handler, for `functions<Contracts>()` in
 * `better-supabase/client`.
 */
export type ContractOf<T> =
  T extends TypedFunction<infer In, infer Out>
    ? FunctionContract<In, Out>
    : never;

type Returned<Out> =
  | Out
  | Result<Out>
  | Response
  | PromiseLike<Out | Result<Out> | Response>
  | undefined;

export interface FunctionDefinition<
  I extends StandardSchemaV1,
  Out,
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C,
  P,
  B,
> extends MiddlewareOptions {
  /** Parses the JSON body. A body it rejects answers 422 with the issues. */
  readonly input: I;
  /**
   * Checks what the handler returns before it is sent. A value it rejects
   * answers 500, so a function never sends data its contract doesn't promise.
   */
  readonly output?: StandardSchemaV1<unknown, Out>;
  /**
   * A one-line summary for the operation `functionRoute` describes in
   * `better-supabase/spec`.
   */
  readonly summary?: string;
  /** Runs as the caller with the parsed input. Returns data or a `Result`. */
  readonly handler: (
    input: StandardSchemaV1.InferOutput<I>,
    ctx: ServerContext<M, F, E, C, P, B> & { readonly request: Request },
  ) => Returned<Out>;
}

async function readInput(request: Request): Promise<Result<unknown>> {
  if (request.method === "GET" || request.method === "HEAD") {
    return ok(undefined);
  }

  const text = await request.text();

  if (text === "") {
    return ok(undefined);
  }

  try {
    return ok(JSON.parse(text));
  } catch {
    return err(dbError("invalid_input", "The request body is not JSON"));
  }
}

/**
 * An Edge Function with a typed input and output: the body is parsed and
 * checked with a Standard Schema (zod, valibot, arktype, ...) before the
 * handler runs as the caller. Its type carries the contract, so the app calls
 * it through `functions<Contracts>()` from `better-supabase/client`.
 *
 * ```ts
 * const sendInvite = defineFunction(bs, {
 *   input: z.object({ email: z.email() }),
 *   handler: (input, ctx) => ctx.db.invites.create({ data: input }),
 * });
 * export type SendInvite = ContractOf<typeof sendInvite>;
 * Deno.serve(sendInvite);
 * ```
 */
export function defineFunction<
  I extends StandardSchemaV1,
  Out,
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  B = unknown,
>(
  edge: Pick<BetterEdge<M, F, E, C, P, string, B>, "handler">,
  definition: FunctionDefinition<I, Out, M, F, E, C, P, B>,
): TypedFunction<StandardSchemaV1.InferInput<I>, Out> {
  const { input, output, summary, handler, ...options } = definition;

  const fn = edge.handler(async (request, ctx) => {
    const body = await readInput(request);

    if (!body.ok) {
      return body;
    }

    const parsed = await validate(input, body.data, "input");

    if (!parsed.ok) {
      return parsed;
    }

    const settled = await settle(() =>
      handler(parsed.data, withExtra(ctx, { request })),
    );

    if (!settled.ok) {
      return err(settled.error);
    }

    if (output === undefined || settled.data instanceof Response) {
      return settled.data;
    }

    const checked = await validate(output, settled.data, "output");

    return checked.ok
      ? checked.data
      : err(
          dbError(
            "unexpected",
            "The function returned data its output rejects",
          ),
        );
  }, options);

  const descriptor: FunctionDescriptor = {
    input,
    ...(output ? { output } : {}),
    ...(summary === undefined ? {} : { summary }),
  };

  Object.defineProperty(fn, FUNCTION_DESCRIPTOR, { value: descriptor });

  // SAFETY: the line above defined the descriptor on fn.
  return fn as TypedFunction<StandardSchemaV1.InferInput<I>, Out>;
}
