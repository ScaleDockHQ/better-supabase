import { describe, expect, it } from "vitest";

import { explorerOverrides } from "../../src/flags-sdk/index.ts";
import { flagOverrideCookie } from "../../src/testing/index.ts";

const jar = (name: string, value: string) => ({
  get: (key: string) => (key === name ? { name, value } : undefined),
});

describe("flagOverrideCookie", () => {
  it("writes the cookie explorerOverrides() reads", async () => {
    const cookie = await flagOverrideCookie({ checkout: "b", beta: true });

    expect(cookie.name).toBe("vercel-flag-overrides");
    expect(cookie.header).toBe(`vercel-flag-overrides=${cookie.value}`);
    expect(await explorerOverrides(jar(cookie.name, cookie.value))).toEqual({
      checkout: "b",
      beta: true,
    });
  });

  it("encrypts through the injected function", async () => {
    const cookie = await flagOverrideCookie(
      { beta: true },
      {
        encrypt: (values) =>
          Promise.resolve(`sealed:${JSON.stringify(values)}`),
      },
    );

    expect(cookie.value).toBe('sealed:{"beta":true}');
    expect(
      await explorerOverrides(jar(cookie.name, cookie.value), {
        decrypt: (value) =>
          Promise.resolve(JSON.parse(value.slice("sealed:".length))),
      }),
    ).toEqual({ beta: true });
  });
});
