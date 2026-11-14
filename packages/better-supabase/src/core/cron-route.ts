import type { ProblemFormat } from "./problem.ts";

import { dbError } from "./errors.ts";
import { methodNotAllowed, problemResponse } from "./problem.ts";
import { verifySharedSecret } from "./signatures.ts";

/**
 * A caller a cron route accepts without the bearer secret. `"vercel-schedule"`
 * is a Vercel schedule run on a private function: Vercel sends it no secret,
 * and the `schedule/v1beta` trigger leaves the function without a public URL.
 */
export type CronCaller = "vercel-schedule";

/** The `ce-type` Vercel Schedules sends to function and path targets. */
const VERCEL_SCHEDULE_TYPE = "com.vercel.schedule.v1beta";

/** What a cron route needs to guard its handler. */
export interface CronRouteGuard {
  /** `drain`, `relay` or `deliver`: names the route in its errors. */
  readonly name: string;
  /** The bearer token callers send, such as `process.env.CRON_SECRET`. */
  readonly secret: string | undefined;
  /** Rewrites the Problem Details body of the 401. */
  readonly problem?: ProblemFormat | undefined;
  /**
   * Also accept this caller without the secret. Only behind a trigger that
   * keeps the route private: anyone can send the header to a public URL.
   */
  readonly caller?: CronCaller | undefined;
}

function fromCaller(request: Request, caller: CronCaller | undefined): boolean {
  switch (caller) {
    case undefined: {
      return false;
    }

    case "vercel-schedule": {
      return request.headers.get("ce-type") === VERCEL_SCHEDULE_TYPE;
    }

    default: {
      const unknown: never = caller;

      return unknown;
    }
  }
}

/**
 * A `GET` or `POST` handler for a cron caller such as Vercel Cron. It throws
 * when the secret is missing (unless `caller` is set), answers 405 to other
 * methods and 401 without the bearer secret or the caller, and only then calls
 * `handle` with the request path.
 */
export function cronRoute(
  guard: CronRouteGuard,
  handle: (request: Request, instance: string) => Promise<Response>,
): (request: Request) => Promise<Response> {
  const { name, secret, caller } = guard;

  if (!secret && caller === undefined) {
    throw new TypeError(
      `${name}Route needs a secret, such as process.env.CRON_SECRET`,
    );
  }

  return async (request) => {
    const instance = new URL(request.url).pathname;

    if (request.method !== "GET" && request.method !== "POST") {
      return methodNotAllowed(["GET", "POST"]);
    }

    const authorized =
      (secret ? verifySharedSecret(request, secret) : false) ||
      fromCaller(request, caller);

    if (!authorized) {
      return problemResponse(
        dbError("unauthorized", `The ${name} route needs its bearer secret`),
        { instance, format: guard.problem },
      );
    }

    return handle(request, instance);
  };
}
