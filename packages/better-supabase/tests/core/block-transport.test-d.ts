import type { SupabaseClient } from "@supabase/supabase-js";

import { createServerClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";
import { describe, it } from "vitest";

import type { Database } from "../fixtures/database.types.ts";

import { rpcTransport } from "../../src/core/block-transport.ts";

describe("rpcTransport", () => {
  it("takes a typed and an untyped supabase-js client without a cast", () => {
    const typed = createClient<Database>("", "");
    const ssr = createServerClient<Database>("", "", {
      cookies: { getAll: () => [] },
    });
    const untyped = {} as SupabaseClient;
    rpcTransport(typed);
    rpcTransport(ssr);
    rpcTransport(untyped, { schema: "api" });
    const other = {} as SupabaseClient<Database, "public">;
    rpcTransport(other);
  });
});
