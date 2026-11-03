import { describe, expect, it } from "vitest";

import { isLoopbackAlias } from "../../src/auth/issuer.ts";

describe("isLoopbackAlias", () => {
  const project = "http://127.0.0.1:54321/auth/v1";

  it("accepts a loopback name and a configured alias for a local project", () => {
    expect(isLoopbackAlias(project, "http://localhost:54321/auth/v1")).toBe(
      true,
    );
    expect(
      isLoopbackAlias(project, "http://192.168.1.20:54321/auth/v1", [
        "192.168.1.20",
      ]),
    ).toBe(true);
  });

  it("refuses an unparsable URL, another port and a hosted project", () => {
    expect(isLoopbackAlias(project, "not a url")).toBe(false);
    expect(isLoopbackAlias(project, "http://localhost:9999/auth/v1")).toBe(
      false,
    );
    expect(
      isLoopbackAlias(
        "https://abc.supabase.co/auth/v1",
        "http://localhost:54321/auth/v1",
      ),
    ).toBe(false);
  });
});
