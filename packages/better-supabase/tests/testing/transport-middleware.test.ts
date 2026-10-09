import { describe, expect, it } from "vitest";

import { defineTransportMiddleware } from "../../src/core/block-hooks.ts";
import { testBlockTransportMiddleware } from "../../src/testing/index.ts";

describe("testBlockTransportMiddleware", () => {
  it("passes middleware that adds an argument and keeps errors", async () => {
    const report = await testBlockTransportMiddleware(
      defineTransportMiddleware({
        name: "request-id",
        call: (request, next) =>
          next({ ...request, args: { ...request.args, request_id: "r1" } }),
      }),
    );
    expect(report.checks.every((check) => check.ok)).toBe(true);
  });

  it("fails middleware that swallows errors or retries blindly", async () => {
    await expect(
      testBlockTransportMiddleware(
        defineTransportMiddleware({
          name: "swallow",
          call: async (request, next) => {
            try {
              return await next(request);
            } catch {
              return next(request).catch(() => null);
            }
          },
        }),
      ),
    ).rejects.toThrow(/failed 1 of 4[\s\S]*resolved although next rejected/);
  });

  it("fails middleware that wraps the database error", async () => {
    await expect(
      testBlockTransportMiddleware(
        defineTransportMiddleware({
          name: "wrap",
          call: (request, next) =>
            next(request).catch((cause: unknown) => {
              throw new Error("wrapped", { cause });
            }),
        }),
      ),
    ).rejects.toThrow(/lost the database error/);
  });
});
