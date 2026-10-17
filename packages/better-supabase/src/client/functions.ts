import {
  type FunctionInvokeOptions,
  FunctionsFetchError,
  FunctionsHttpError,
  FunctionsRelayError,
} from "@supabase/supabase-js";

import type { FunctionContract } from "../core/function-contract.ts";

import { type DbError, dbError } from "../core/errors.ts";
import { fromProblem, isProblem } from "../core/problem.ts";
import { AsyncResult, err, ok } from "../core/result.ts";

export type { FunctionContract };

/** `supabase.functions.invoke` options, without the body: `invoke` sends the input. */
export type InvokeOptions = Omit<FunctionInvokeOptions, "body">;

/** Edge Function contracts by function name. */
export type FunctionContracts = Readonly<Record<string, FunctionContract>>;

/** Anything with supabase-js's `functions` client, e.g. a `SupabaseClient`. */
export interface FunctionsHost {
  readonly functions: {
    invoke(
      name: string,
      options?: FunctionInvokeOptions,
    ): Promise<{ data: unknown; error: unknown; response?: Response }>;
  };
}

export interface TypedFunctions<Contracts extends FunctionContracts> {
  /**
   * Calls the function with `input` as the JSON body. Problem Details from
   * the function come back as their `DbError`; a network or relay failure is
   * a `network` error.
   */
  invoke<N extends keyof Contracts & string>(
    name: N,
    ...[input, options]: undefined extends Contracts[N]["input"]
      ? [input?: Contracts[N]["input"], options?: InvokeOptions]
      : [input: Contracts[N]["input"], options?: InvokeOptions]
  ): AsyncResult<Contracts[N]["output"]>;
}

function withJson(
  headers: Readonly<Record<string, string>> = {},
): Record<string, string> {
  return Object.keys(headers).some(
    (key) => key.toLowerCase() === "content-type",
  )
    ? { ...headers }
    : { ...headers, "content-type": "application/json" };
}

function causeName(cause: unknown): string | undefined {
  return cause instanceof Error ? cause.name : undefined;
}

async function fromHttp(response: Response, name: string): Promise<DbError> {
  const type = response.headers.get("content-type") ?? "";

  if (type.includes("json")) {
    const body: unknown = await response.json().catch(() => undefined);

    if (isProblem(body)) {
      return fromProblem(body);
    }
  }

  return dbError("unexpected", `${name} answered ${String(response.status)}`, {
    status: response.status,
  });
}

/** The function's error as a `DbError`. */
async function toFunctionError(error: unknown, name: string): Promise<DbError> {
  if (
    error instanceof FunctionsHttpError &&
    error.context instanceof Response
  ) {
    return fromHttp(error.context, name);
  }

  if (error instanceof FunctionsFetchError) {
    const cause: unknown = error.context;

    if (causeName(cause) === "AbortError") {
      return dbError("aborted", `The call to ${name} was aborted`);
    }

    if (causeName(cause) === "TimeoutError") {
      return dbError("timeout", `The call to ${name} timed out`);
    }

    return dbError("network", `Could not reach ${name}`);
  }

  if (error instanceof FunctionsRelayError) {
    return dbError("network", `The Edge Functions relay failed to run ${name}`);
  }

  return dbError(
    "unexpected",
    error instanceof Error ? error.message : `${name} failed`,
  );
}

/**
 * Typed Edge Function calls over supabase-js's `functions` client. The
 * contracts come from the functions' own code, imported as types:
 *
 * ```ts
 * import type { SendInvite } from "../supabase/functions/send-invite/index.ts";
 *
 * const fns = functions<{ "send-invite": SendInvite }>(supabase);
 * const invite = await fns.invoke("send-invite", { email }).orThrow();
 * ```
 */
export function functions<Contracts extends FunctionContracts>(
  host: FunctionsHost,
): TypedFunctions<Contracts> {
  return {
    invoke(name, ...[input, options]) {
      return AsyncResult.from(async () => {
        const { data, error, response } = await host.functions.invoke(
          name,
          input === undefined
            ? options
            : {
                ...options,
                headers: withJson(options?.headers),
                body: JSON.stringify(input),
              },
        );

        if (error !== null && error !== undefined) {
          return err(await toFunctionError(error, name));
        }

        // SAFETY: the function's output schema and the contract it exports
        // describe this body; a 204 carries no data.
        return ok(
          (response?.status === 204
            ? undefined
            : data) as Contracts[typeof name]["output"],
        );
      });
    },
  };
}
