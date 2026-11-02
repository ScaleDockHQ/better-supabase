import { describe, expect, it } from "vitest";

import type { WebAuthnApi } from "../../src/blocks/mfa/client.ts";

import { SPEC_PINS } from "../../src/core/spec-pins.ts";

describe("WebAuthn Level 3", () => {
  it("pins the level", () => {
    expect(SPEC_PINS.webauthn).toBe("3");
  });

  it("accepts the shape of supabase-js `auth.mfa.webauthn`", () => {
    // The relying party options are the ones Level 3 names: rpId and origins.
    const api: WebAuthnApi = {
      register: () => Promise.resolve({ data: {}, error: null }),
      authenticate: () => Promise.resolve({ data: {}, error: null }),
    };

    expect(Object.keys(api).toSorted()).toEqual(["authenticate", "register"]);
  });
});
