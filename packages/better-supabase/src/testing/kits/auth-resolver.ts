import type { AuthResolver, AuthState } from "../../auth/resolve.ts";
import type { ConformanceReport } from "../conformance.ts";

import { Violation, conform, expect } from "../conformance.ts";
import { hasName } from "./executor.ts";

export interface TestAuthResolverOptions {
  /** Requests with credentials this resolver owns but that must not verify. */
  readonly invalid: readonly Request[];
  /**
   * Requests that must resolve to a user or service, optionally with the
   * expected user id.
   */
  readonly valid?: readonly {
    readonly request: Request;
    readonly userId?: string;
  }[];
  /** A request without this resolver's credentials. Defaults to a bare GET. */
  readonly unrelated?: Request;
}

async function resolveSafely(
  resolver: AuthResolver,
  request: Request,
): Promise<AuthState | undefined> {
  try {
    return await resolver.resolve(request);
  } catch (cause) {
    throw new Violation(
      `resolve() threw: ${cause instanceof Error ? cause.message : String(cause)}`,
    );
  }
}

/**
 * Proves an `AuthResolver` passes on requests it doesn't understand, fails
 * closed (`invalid`, never anon) on bad credentials, and never throws.
 */
export function testAuthResolver(
  resolver: AuthResolver,
  options: TestAuthResolverOptions,
): Promise<ConformanceReport> {
  return conform(`AuthResolver "${resolver.name}"`, [
    hasName(resolver),
    [
      "passes on requests without its credentials",
      async () => {
        const state = await resolveSafely(
          resolver,
          options.unrelated ?? new Request("https://example.com/"),
        );

        expect(
          state === undefined,
          `expected undefined, got kind "${state?.kind}"`,
        );
      },
    ],
    [
      "fails closed on invalid credentials",
      async () => {
        expect(options.invalid.length > 0, "pass at least one invalid request");

        for (const request of options.invalid) {
          const state = await resolveSafely(resolver, request);
          expect(
            state?.kind === "invalid",
            `expected kind "invalid", got "${state?.kind ?? "undefined"}"`,
          );
          expect(
            typeof state.error.kind === "string",
            "invalid states carry a DbError",
          );
        }
      },
    ],
    options.valid && [
      "resolves valid credentials",
      async () => {
        for (const { request, userId } of options.valid!) {
          const state = await resolveSafely(resolver, request);
          expect(
            state?.kind === "user" || state?.kind === "secret",
            `expected a user or service, got "${state?.kind}"`,
          );

          if (userId !== undefined) {
            expect(
              state.kind === "user" && state.user.id === userId,
              `expected user ${userId}`,
            );
          }
        }
      },
    ],
  ]);
}
