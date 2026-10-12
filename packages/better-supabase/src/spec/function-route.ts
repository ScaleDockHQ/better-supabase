import type {
  DescribedFunction,
  FunctionDescriptor,
} from "../core/function-contract.ts";
import type { RouteSpec } from "./options.ts";

import { FUNCTION_DESCRIPTOR } from "../core/function-contract.ts";

export interface FunctionRouteOptions {
  /** Defaults to `POST`. */
  readonly method?: RouteSpec["method"];
  /** Defaults to the function's own `summary`. */
  readonly summary?: string;
  readonly tags?: readonly string[];
}

function isDescriptor(value: unknown): value is FunctionDescriptor {
  return typeof value === "object" && value !== null && "input" in value;
}

function descriptorOf(fn: unknown): FunctionDescriptor | undefined {
  if (typeof fn !== "function" || !(FUNCTION_DESCRIPTOR in fn))
    return undefined;
  const descriptor: unknown = fn[FUNCTION_DESCRIPTOR];
  return isDescriptor(descriptor) ? descriptor : undefined;
}

/**
 * The route of a `defineFunction` handler, at `/functions/v1/<name>`: its
 * input is the request body and its output the 200 response. Pass it in
 * `routes`; `basePath` goes in front of it like any other route.
 *
 * ```ts
 * defineApi(bs, { routes: [functionRoute("send-invite", sendInvite)] });
 * ```
 */
export function functionRoute(
  name: string,
  fn: DescribedFunction,
  options: FunctionRouteOptions = {},
): RouteSpec {
  const descriptor = descriptorOf(fn);
  if (!descriptor) {
    throw new TypeError(
      `better-supabase/spec: functionRoute("${name}") needs a handler from defineFunction`,
    );
  }
  const summary = options.summary ?? descriptor.summary;
  return {
    method: options.method ?? "post",
    path: `/functions/v1/${name}`,
    input: descriptor.input,
    ...(descriptor.output ? { output: descriptor.output } : {}),
    ...(summary === undefined ? {} : { summary }),
    ...(options.tags ? { tags: options.tags } : {}),
  };
}
