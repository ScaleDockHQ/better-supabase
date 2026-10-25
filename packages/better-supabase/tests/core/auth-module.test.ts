import { describe, expect, it } from "vitest";

import { authModuleOf, hasAuthModule } from "../../src/core/auth-module.ts";
import { relayRealtimeClient } from "../../src/realtime/relay.ts";

describe("authModuleOf", () => {
  it("finds a supabase-js auth module", () => {
    const auth = { onAuthStateChange: () => ({ data: {} }) };

    expect(authModuleOf({ auth })).toBe(auth);
    expect(hasAuthModule({ auth })).toBe(true);
  });

  it("has none for clients without a followable auth module", () => {
    expect(hasAuthModule(relayRealtimeClient("/rt"))).toBe(false);
    expect(authModuleOf({ auth: null })).toBeUndefined();
    expect(authModuleOf({ auth: "x" })).toBeUndefined();
    expect(authModuleOf({ auth: {} })).toBeUndefined();
    expect(authModuleOf({ auth: { onAuthStateChange: true } })).toBeUndefined();
  });
});
