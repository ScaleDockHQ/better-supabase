import type {
  BlockTransportMiddleware,
  BlockTransportRequest,
} from "../core/block-hooks.ts";
import type { ConformanceReport } from "./conformance.ts";

import { rawError } from "../core/block-transport.ts";
import { conform, expect, frozenCopy, hasName } from "./conformance.ts";

const REQUEST: BlockTransportRequest = {
  schema: "better_supabase",
  fn: "list_my_organizations",
  args: { organization: "organization_1", filters: { status: "open" } },
};

/**
 * Proves a `BlockTransportMiddleware` meets the contract: it declares API 1
 * and a name, calls `next` at most once per call, leaves the request it got
 * unchanged, resolves when `next` does, and rejects with the database error
 * `next` rejected with, so blocks still map it to a `DbError`.
 *
 * ```ts
 * it('conforms', () => testBlockTransportMiddleware(statementTimeout('5s')));
 * ```
 */
export function testBlockTransportMiddleware(
  middleware: BlockTransportMiddleware,
): Promise<ConformanceReport> {
  return conform(`BlockTransportMiddleware "${middleware.name}"`, [
    hasName(middleware),
    [
      "declares apiVersion 1",
      () => {
        const version: unknown = middleware.apiVersion;
        expect(version === 1, "apiVersion must be 1");
      },
    ],
    [
      "calls next at most once and resolves with a value",
      async () => {
        let calls = 0;
        await middleware.call(frozenCopy(REQUEST), (request) => {
          calls += 1;
          expect(
            typeof request.fn === "string" &&
              typeof request.schema === "string",
            "next got a request without a schema and function",
          );
          return Promise.resolve([{ id: "organization_1" }]);
        });
        expect(calls <= 1, `next was called ${String(calls)} times`);
      },
    ],
    [
      "keeps the database error next rejects with",
      async () => {
        const denied = Object.assign(new Error("permission denied"), {
          code: "42501",
          hint: "ORGANIZATION_FORBIDDEN",
        });
        let rejected: unknown;
        try {
          await middleware.call(frozenCopy(REQUEST), () =>
            Promise.reject(denied),
          );
        } catch (cause) {
          rejected = cause;
        }
        expect(rejected !== undefined, "resolved although next rejected");
        const raw = rawError(rejected);
        expect(
          raw?.code === "42501" && raw.hint === "ORGANIZATION_FORBIDDEN",
          "the rejection lost the database error's code or hint",
        );
      },
    ],
  ]);
}
