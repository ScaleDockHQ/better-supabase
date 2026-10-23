import type { SupabaseClient } from "@supabase/supabase-js";

import { describe, expectTypeOf, it } from "vitest";

import type { AuthzVersionClient } from "../../src/server/authz-versions.ts";

describe("AuthzVersionClient", () => {
  it("accepts a supabase-js client", () => {
    expectTypeOf<SupabaseClient>().toExtend<AuthzVersionClient>();
  });
});
