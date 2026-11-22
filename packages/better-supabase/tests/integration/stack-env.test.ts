import { describe, expect, it } from "vitest";

import { tlsFailure } from "./stack-env.ts";

describe("tlsFailure", () => {
  it("names a certificate failure", () => {
    const error = new TypeError("fetch failed", {
      cause: Object.assign(new Error("self signed"), {
        code: "DEPTH_ZERO_SELF_SIGNED_CERT",
      }),
    });

    expect(tlsFailure(error)).toBe("DEPTH_ZERO_SELF_SIGNED_CERT");
  });

  it("leaves a refused connection as unreachable", () => {
    const error = new TypeError("fetch failed", {
      cause: Object.assign(new Error("refused"), { code: "ECONNREFUSED" }),
    });

    expect(tlsFailure(error)).toBeUndefined();
    expect(tlsFailure(new Error("x"))).toBeUndefined();
  });
});
