import { createClient } from "@supabase/supabase-js";
import { describe, expect, it } from "vitest";

import { createFakePostgrest } from "../../src/testing/fake-postgrest.ts";

const client = (api: ReturnType<typeof createFakePostgrest>) =>
  createClient("http://stack.test", "key", {
    global: { fetch: api.fetch },
    auth: { persistSession: false, autoRefreshToken: false },
  });

describe("createFakePostgrest", () => {
  it("answers the real client's select, with the query and schema the handler sees", async () => {
    const api = createFakePostgrest(() => ({ data: [{ id: 1 }] }));

    const reply = await client(api)
      .schema("api")
      .from("notes")
      .select("id")
      .eq("owner", "u1");

    expect(reply.data).toEqual([{ id: 1 }]);
    expect(api.requests[0]).toMatchObject({
      method: "GET",
      path: "/notes",
      schema: "api",
      query: { select: "id", owner: "eq.u1" },
    });
  });

  it("answers an insert, a count and a single like PostgREST", async () => {
    const api = createFakePostgrest(() => ({ data: [], count: 7 }));
    const supabase = client(api);

    const inserted = await supabase.from("notes").insert({ a: 1 });
    expect(inserted.error).toBeNull();
    expect(api.requests[0]).toMatchObject({ method: "POST", body: { a: 1 } });

    const counted = await supabase
      .from("notes")
      .select("*", { count: "exact", head: true });

    expect(counted.count).toBe(7);

    const single = await supabase.from("notes").select().single();
    expect(single.error?.code).toBe("PGRST116");
  });

  it("returns the handler's error and rpc results", async () => {
    const api = createFakePostgrest((request) =>
      request.path === "/rpc/boom"
        ? { error: { message: "no", code: "42501" } }
        : { data: 3 },
    );

    const supabase = client(api);

    expect((await supabase.rpc("boom")).error?.code).toBe("42501");
    expect((await supabase.rpc("count_notes")).data).toBe(3);
  });
});
