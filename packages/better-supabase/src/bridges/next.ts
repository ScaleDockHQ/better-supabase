import type { AnyEntry, Contributions } from "@supabase/middleware";

import type { Validated } from "./shared.ts";

import { around, bufferInPlace, toResponse } from "./shared.ts";

/** The second argument Next.js passes to a route handler. */
export interface NextRouteContext<Params = Record<string, string | string[]>> {
  readonly params: Promise<Params>;
}

/** A Next.js route handler (`export const GET = ...`). */
export type NextRouteHandler<Params = Record<string, string | string[]>> = (
  request: Request,
  context: NextRouteContext<Params>,
) => Promise<Response>;

export interface ToNextRouteOptions {
  /** The host's env object for `getEnv`, read per request. */
  readonly env?: (request: Request) => unknown;
}

/**
 * Runs an entry array around a Next.js route handler. The handler gets the
 * entries' contributions as `ctx` and may return a `Response` or a value (sent
 * as JSON, `undefined` as 204). Response-phase entries (`withCors`, refreshed
 * cookies) see the handler's response.
 *
 * ```ts
 * // src/app/api/notes/route.ts
 * export const GET = toNextRoute(
 *   [withCors(cors), withRequiredClaims(), withSupabaseClient()],
 *   async (request, ctx) =>
 *     (await ctx.supabase.from("notes").select()).data,
 * );
 * ```
 */
export function toNextRoute<
  const Entries extends readonly AnyEntry[],
  Params = Record<string, string | string[]>,
>(
  entries: Entries & Validated<Entries>,
  handler: (
    request: Request,
    ctx: Contributions<Entries>,
    context: NextRouteContext<Params>,
  ) => unknown,
  options: ToNextRouteOptions = {},
): NextRouteHandler<Params> {
  const run = around(entries);

  return async (request, context) => {
    bufferInPlace(request);

    return run(request, options.env?.(request), async (contributions) =>
      toResponse(
        await handler(
          request,
          // SAFETY: around() hands over exactly the entries' contributions.
          contributions as Contributions<Entries>,
          context,
        ),
      ),
    );
  };
}

/**
 * The attributes of a `Set-Cookie` header, as Next.js `cookies().set` takes
 * them.
 */
export interface NextCookieWrite {
  readonly name: string;
  readonly value: string;
  readonly path?: string;
  readonly domain?: string;
  readonly maxAge?: number;
  readonly expires?: Date;
  readonly httpOnly?: boolean;
  readonly secure?: boolean;
  readonly sameSite?: "lax" | "strict" | "none";
  readonly partitioned?: boolean;
}

/** The parts of a Server Action's request the bridge reads and writes. */
export interface NextActionIO {
  /** The incoming headers (`await headers()`), cookie header included. */
  readonly headers: () => Promise<Headers>;
  /** Writes a cookie the entries set (`(await cookies()).set`). */
  readonly setCookie: (write: NextCookieWrite) => Promise<void>;
}

/**
 * Thrown by an action whose entries answered before the action ran, such as
 * `withRequiredClaims` with a 401 for a caller without a session.
 */
export class NextActionRejected extends Error {
  readonly status: number;
  readonly response: Response;

  constructor(response: Response) {
    super(`The action was rejected with status ${String(response.status)}.`);
    this.name = "NextActionRejected";
    this.status = response.status;
    this.response = response;
  }
}

export interface ToNextActionOptions {
  /** The host's env object for `getEnv`, read per call. */
  readonly env?: (request: Request) => unknown;
}

/**
 * The `Request` of a Server Action: a POST to the page that called it, with the
 * incoming headers. Next.js gives actions no `Request`, so the entries see this
 * one.
 */
export function actionRequest(headers: Headers): Request {
  const host = headers.get("x-forwarded-host") ?? headers.get("host");
  const protocol = headers.get("x-forwarded-proto") ?? "https";
  const origin = host ? `${protocol}://${host}` : "http://localhost";
  const path = headers.get("next-url") ?? "/";

  return new Request(new URL(path, origin), { method: "POST", headers });
}

/**
 * Runs an entry array around a Server Action with `io` reading the request and
 * writing cookies. `src/next` binds `io` to `headers()` and `cookies()`.
 */
export function nextAction<
  const Entries extends readonly AnyEntry[],
  Args extends unknown[],
  Result,
>(
  entries: Entries & Validated<Entries>,
  action: (ctx: Contributions<Entries>, ...args: Args) => Promise<Result>,
  io: NextActionIO,
  options: ToNextActionOptions = {},
): (...args: Args) => Promise<Result> {
  const run = around(entries);

  return async (...args) => {
    const request = actionRequest(await io.headers());
    const outcome: { ran: boolean; result?: Result } = { ran: false };

    const response = await run(
      request,
      options.env?.(request),
      async (contributions) => {
        outcome.result = await action(
          // SAFETY: around() hands over exactly the entries' contributions.
          contributions as Contributions<Entries>,
          ...args,
        );

        outcome.ran = true;

        return new Response(null, { status: 204 });
      },
    );

    for (const header of response.headers.getSetCookie()) {
      const write = parseSetCookie(header);

      if (write) {
        await io.setCookie(write);
      }
    }

    if (!outcome.ran) {
      throw new NextActionRejected(response);
    }

    // SAFETY: `ran` is set only after the action resolved with its result.
    return outcome.result as Result;
  };
}

const SAME_SITE = new Set(["lax", "strict", "none"]);

function isSameSite(value: string): value is "lax" | "strict" | "none" {
  return SAME_SITE.has(value);
}

/**
 * One `Set-Cookie` header as a cookie write, or `undefined` when it has no
 * name.
 */
export function parseSetCookie(header: string): NextCookieWrite | undefined {
  const [pair = "", ...attributes] = header.split(";");
  const equals = pair.indexOf("=");

  if (equals <= 0) {
    return undefined;
  }

  const write: {
    -readonly [Key in keyof NextCookieWrite]: NextCookieWrite[Key];
  } = {
    name: pair.slice(0, equals).trim(),
    value: decodeURIComponent(pair.slice(equals + 1).trim()),
  };

  for (const attribute of attributes) {
    const at = attribute.indexOf("=");

    const key = (at === -1 ? attribute : attribute.slice(0, at))
      .trim()
      .toLowerCase();

    const value = at === -1 ? "" : attribute.slice(at + 1).trim();

    switch (key) {
      case "path": {
        write.path = value;
        break;
      }

      case "domain": {
        write.domain = value;
        break;
      }

      case "max-age": {
        const seconds = Number(value);

        if (Number.isFinite(seconds)) {
          write.maxAge = seconds;
        }

        break;
      }

      case "expires": {
        const date = new Date(value);

        if (!Number.isNaN(date.getTime())) {
          write.expires = date;
        }

        break;
      }

      case "httponly": {
        write.httpOnly = true;
        break;
      }

      case "secure": {
        write.secure = true;
        break;
      }

      case "samesite": {
        const sameSite = value.toLowerCase();

        if (isSameSite(sameSite)) {
          write.sameSite = sameSite;
        }

        break;
      }

      case "partitioned": {
        write.partitioned = true;
        break;
      }

      default: {
        break;
      }
    }
  }

  return write;
}
