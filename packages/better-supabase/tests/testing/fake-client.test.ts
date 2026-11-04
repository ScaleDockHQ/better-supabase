import { describe, expect, it } from "vitest";

import { createFakeClient } from "../../src/testing/fake-client.ts";

describe("createFakeClient", () => {
  it("records method, path, query and body", async () => {
    const client = createFakeClient(() => ({ data: [{ id: 1 }] }));

    const reply = await client
      .from("notes")
      .select("id")
      .eq("owner", "u1")
      .in("id", [1, 2])
      .order("id", { ascending: false })
      .limit(5);

    expect(reply.data).toEqual([{ id: 1 }]);
    expect(client.requests[0]).toMatchObject({
      method: "GET",
      path: "/notes",
      schema: "public",
      query: {
        select: "id",
        owner: "eq.u1",
        id: "in.(1,2)",
        order: "id.desc",
        limit: "5",
      },
    });

    await client.from("notes").insert({ title: "a" });
    expect(client.requests[1]).toMatchObject({
      method: "POST",
      body: { title: "a" },
    });
  });

  it("answers single() and maybeSingle() like PostgREST", async () => {
    const client = createFakeClient(() => ({ data: [] }));

    expect((await client.from("t").select().single()).error?.code).toBe(
      "PGRST116",
    );
    expect(await client.from("t").select().maybeSingle()).toMatchObject({
      data: null,
      error: null,
    });
  });

  it("supports schema() and rpc()", async () => {
    const client = createFakeClient(() => ({ data: 3 }));

    const reply = await client.schema("api").rpc("count_notes", { a: 1 });

    expect(reply.data).toBe(3);
    expect(client.requests[0]).toMatchObject({
      method: "POST",
      path: "/rpc/count_notes",
      body: { a: 1 },
    });
  });
});
