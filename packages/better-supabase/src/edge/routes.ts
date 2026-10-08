import type { AnyFunctions, AnyModels } from "../schema/types.ts";
import type { EdgeRoute, EdgeRouteHandler, EdgeRoutes } from "./index.ts";

interface CompiledRoute<M extends AnyModels, F extends AnyFunctions, E, C, P> {
  readonly method: string | undefined;
  readonly segments: readonly string[];
  readonly rest: boolean;
  readonly handler: EdgeRouteHandler<M, F, E, C, P>;
  readonly options: Omit<EdgeRoute<M, F, E, C, P>, "handler">;
}

/** A matched route and its decoded params. */
export interface RouteMatch<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C,
  P,
> {
  readonly route: CompiledRoute<M, F, E, C, P>;
  readonly params: Readonly<Record<string, string>>;
}

const METHOD = /^([A-Z]+)\s+(\/.*)$/;

function split(path: string): string[] {
  return path.split("/").filter((segment) => segment !== "");
}

/** Parses `"METHOD /path"` keys once; static routes sort before params. */
export function compileRoutes<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C,
  P,
>(routes: EdgeRoutes<M, F, E, C, P>): CompiledRoute<M, F, E, C, P>[] {
  const compiled: CompiledRoute<M, F, E, C, P>[] = [];
  for (const [key, value] of Object.entries(routes)) {
    const matched = METHOD.exec(key.trim());
    const method = matched?.[1];
    const path = matched?.[2] ?? key.trim();
    if (!path.startsWith("/")) {
      throw new TypeError(
        `better-supabase: route "${key}" must be "/path" or "METHOD /path"`,
      );
    }
    const segments = split(path);
    const rest = segments.at(-1) === "*";
    if (rest) segments.pop();
    const { handler, ...options } =
      typeof value === "function" ? { handler: value } : value;
    compiled.push({ method, segments, rest, handler, options });
  }
  const weight = (route: CompiledRoute<M, F, E, C, P>): number =>
    route.segments.filter((segment) => segment.startsWith(":")).length +
    (route.rest ? 100 : 0);
  return compiled.toSorted((a, b) => weight(a) - weight(b));
}

function paramsOf(
  segments: readonly string[],
  rest: boolean,
  parts: readonly string[],
): Record<string, string> | undefined {
  if (rest ? parts.length < segments.length : parts.length !== segments.length)
    return undefined;
  const params: Record<string, string> = {};
  for (const [index, segment] of segments.entries()) {
    const part = parts[index] ?? "";
    if (segment.startsWith(":")) {
      try {
        params[segment.slice(1)] = decodeURIComponent(part);
      } catch {
        return undefined;
      }
    } else if (segment !== part) return undefined;
  }
  if (rest) params["*"] = parts.slice(segments.length).join("/");
  return params;
}

/**
 * The route for `method` and `path`: a match, the allowed methods when the
 * path matches under another method (`HEAD` falls back to `GET`), or `"none"`.
 */
export function matchRoute<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C,
  P,
>(
  routes: readonly CompiledRoute<M, F, E, C, P>[],
  method: string,
  path: string,
): RouteMatch<M, F, E, C, P> | readonly string[] | "none" {
  const parts = split(path);
  const allowed = new Set<string>();
  let fallback: RouteMatch<M, F, E, C, P> | undefined;
  for (const route of routes) {
    const params = paramsOf(route.segments, route.rest, parts);
    if (!params) continue;
    if (route.method === undefined || route.method === method)
      return { route, params };
    if (method === "HEAD" && route.method === "GET")
      fallback ??= { route, params };
    allowed.add(route.method);
  }
  if (fallback) return fallback;
  return allowed.size > 0 ? [...allowed] : "none";
}
