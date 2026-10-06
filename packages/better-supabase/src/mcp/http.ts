import { getEnv } from "@supabase/middleware";
import { fromSupabaseUrl } from "@supabase/server/oauth-protected-resource";

/** The RFC 9728 well-known prefix. The Supabase Edge Functions gateway never routes it to a function. */
const WELL_KNOWN = "/.well-known/oauth-protected-resource";
/** The path suffix `withOAuthProtectedResource` serves, reachable through `/functions/v1/<slug>`. */
const SUFFIX = "/oauth-protected-resource";
/** The prefix the Edge Functions gateway strips before the function sees the request. */
const EDGE_PREFIX = "/functions/v1";

const ALLOW_HEADERS =
  "Authorization, Content-Type, Accept, Mcp-Protocol-Version, Mcp-Session-Id, Mcp-Method, Mcp-Name";

const trim = (value: string): string => value.replace(/\/+$/, "");

/**
 * Whether the request runs on Supabase Edge Functions, detected as
 * `@supabase/server` 1.9 does, minus its plain-Deno fallback so a Deno Deploy
 * server keeps its own URLs.
 */
function onEdgeFunctions(): boolean {
  return ["SUPABASE_FUNCTION_SLUG", "SB_EXECUTION_ID"].some((key) =>
    Boolean(getEnv(key)),
  );
}

/** The public origin: `SUPABASE_PUBLIC_URL`, else the gateway's `X-Forwarded-*` headers. */
function edgeOrigin(request: Request): string {
  const publicUrl = getEnv("SUPABASE_PUBLIC_URL");
  if (publicUrl) return trim(publicUrl);
  const url = new URL(request.url);
  const host = request.headers.get("x-forwarded-host") ?? url.hostname;
  const proto = (
    request.headers.get("x-forwarded-proto") ?? url.protocol.slice(0, -1)
  ).toLowerCase();
  const port = host.includes(":")
    ? ""
    : (request.headers.get("x-forwarded-port") ?? url.port);
  const standard =
    (proto === "https" && port === "443") ||
    (proto === "http" && port === "80");
  return `${proto}://${host}${port && !standard ? `:${port}` : ""}`;
}

function stripMetadata(pathname: string): string {
  if (pathname.startsWith(WELL_KNOWN)) return pathname.slice(WELL_KNOWN.length);
  if (pathname.endsWith(SUFFIX)) return pathname.slice(0, -SUFFIX.length);
  return pathname;
}

function edgePath(request: Request): string {
  const slug = getEnv("SUPABASE_FUNCTION_SLUG");
  if (slug) return `${EDGE_PREFIX}/${slug}`;
  return trim(`${EDGE_PREFIX}${stripMetadata(new URL(request.url).pathname)}`);
}

/** A request for the RFC 9728 metadata, at the well-known prefix or the `{resource}/oauth-protected-resource` suffix. */
export function isMetadataRequest(request: Request): boolean {
  const { pathname } = new URL(request.url);
  if (pathname === WELL_KNOWN || pathname.startsWith(`${WELL_KNOWN}/`)) {
    return true;
  }
  return pathname.endsWith(SUFFIX) && request.method !== "POST";
}

export interface DiscoveryOptions {
  readonly resource?: string | ((request: Request) => string);
  readonly authorizationServers?: readonly string[];
}

export interface Discovery {
  /** The RFC 9728 `resource`: the option, else the public URL of the endpoint. */
  readonly resource: (request: Request) => string;
  /** Where the metadata is served, for `WWW-Authenticate` challenges. */
  readonly metadataUrl: (request: Request) => string;
  readonly authorizationServers: (request: Request) => readonly string[];
  /** The `Host` to check against `allowedHosts`. */
  readonly host: (request: Request) => string | null;
}

/**
 * The public URLs of an MCP endpoint. On Supabase Edge Functions they come
 * from the gateway (the request URL is internal there, without
 * `/functions/v1`), and the metadata is advertised at the suffix route.
 */
export function discovery(
  options: DiscoveryOptions,
  supabaseUrl: () => string,
): Discovery {
  const resource = (request: Request): string => {
    if (typeof options.resource === "function")
      return options.resource(request);
    if (options.resource) return options.resource;
    if (onEdgeFunctions()) return `${edgeOrigin(request)}${edgePath(request)}`;
    const url = new URL(request.url);
    return trim(`${url.origin}${stripMetadata(url.pathname)}`);
  };
  return {
    resource,
    metadataUrl: (request) => {
      const target = new URL(resource(request));
      const path = trim(target.pathname);
      return onEdgeFunctions()
        ? `${target.origin}${path}${SUFFIX}`
        : `${target.origin}${WELL_KNOWN}${path}`;
    },
    authorizationServers: (request) => {
      if (options.authorizationServers) return options.authorizationServers;
      return onEdgeFunctions()
        ? [`${edgeOrigin(request)}/auth/v1`]
        : [fromSupabaseUrl(supabaseUrl())];
    },
    host: (request) => {
      // Outside the gateway a page on the rebinding host could set X-Forwarded-Host itself.
      const forwarded = onEdgeFunctions()
        ? request.headers.get("x-forwarded-host")
        : null;
      return forwarded ?? request.headers.get("host");
    },
  };
}

/** The `OPTIONS` answer for the metadata route. */
export function metadataPreflight(): Response {
  return new Response(null, {
    status: 204,
    headers: {
      "access-control-allow-origin": "*",
      "access-control-allow-methods": "GET, OPTIONS",
      "access-control-allow-headers": "Content-Type, Mcp-Protocol-Version",
    },
  });
}

/** The `OPTIONS` answer for the MCP endpoint. */
export function endpointPreflight(
  request: Request,
  allowedOrigins?: readonly string[],
): Response {
  return withCors(
    new Response(null, {
      status: 204,
      headers: {
        "access-control-allow-methods": "POST, OPTIONS",
        "access-control-allow-headers": ALLOW_HEADERS,
        "access-control-max-age": "86400",
      },
    }),
    request,
    allowedOrigins,
  );
}

/**
 * Adds CORS headers to an endpoint response, keeping any the handler set.
 * With `allowedOrigins` a listed origin is echoed; otherwise any origin may
 * call, which is safe because the token travels in a header, not a cookie.
 */
export function withCors(
  response: Response,
  request: Request,
  allowedOrigins?: readonly string[],
): Response {
  const origin = request.headers.get("origin");
  const allow = allowedOrigins
    ? origin && allowedOrigins.includes(origin)
      ? origin
      : null
    : "*";
  const apply = (headers: Headers): void => {
    if (allow && !headers.has("access-control-allow-origin")) {
      headers.set("access-control-allow-origin", allow);
      if (allow !== "*") headers.append("vary", "Origin");
    }
    if (!headers.has("access-control-expose-headers")) {
      headers.set("access-control-expose-headers", "WWW-Authenticate");
    }
  };
  try {
    apply(response.headers);
    return response;
  } catch {
    const headers = new Headers(response.headers);
    apply(headers);
    return new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers,
    });
  }
}
