import type { ProblemFormat } from "./problem.ts";

import { dbError } from "./errors.ts";
import { methodNotAllowed, problemResponse } from "./problem.ts";
import { verifySharedSecret } from "./signatures.ts";

/** What a cron route needs to guard its handler. */
export interface CronRouteGuard {
  /** `drain`, `relay` or `deliver`: names the route in its errors. */
  readonly name: string;
  /** The bearer token callers send, such as `process.env.CRON_SECRET`. */
  readonly secret: string | undefined;
  /** Rewrites the Problem Details body of the 401. */
  readonly problem?: ProblemFormat | undefined;
}

/**
 * A `GET` or `POST` handler for a cron caller such as Vercel Cron. It throws
 * when the secret is missing, answers 405 to other methods and 401 without the
 * bearer secret, and only then calls `handle` with the request path.
 */
export function cronRoute(
  guard: CronRouteGuard,
  handle: (request: Request, instance: string) => Promise<Response>,
): (request: Request) => Promise<Response> {
  const { name, secret } = guard;

  if (!secret) {
    throw new TypeError(
      `${name}Route needs a secret, such as process.env.CRON_SECRET`,
    );
  }

  return async (request) => {
    const instance = new URL(request.url).pathname;

    if (request.method !== "GET" && request.method !== "POST") {
      return methodNotAllowed(["GET", "POST"]);
    }

    if (!verifySharedSecret(request, secret)) {
      return problemResponse(
        dbError("unauthorized", `The ${name} route needs its bearer secret`),
        { instance, format: guard.problem },
      );
    }

    return handle(request, instance);
  };
}
