import { describe, expect, it } from "vitest";

import { createSupabase } from "../../src/core/define.ts";
import { sessionsRuntime } from "../../src/server/sessions-runtime.ts";
import { schema } from "../fixtures/generated-camel.ts";

const env = {
  SUPABASE_URL: "http://127.0.0.1:54321",
  SUPABASE_PUBLISHABLE_KEY: "pub",
  SUPABASE_SECRET_KEY: "sec",
};

describe("sessionsRuntime", () => {
  it("holds a verified-token memo unless sessions is false", () => {
    const definition = createSupabase(schema);

    expect(
      sessionsRuntime(definition, { env, prefetchJwks: false }).verifiedTokens,
    ).toBeDefined();
    expect(
      sessionsRuntime(definition, { env, sessions: false, prefetchJwks: false })
        .verifiedTokens,
    ).toBeUndefined();
  });
});
