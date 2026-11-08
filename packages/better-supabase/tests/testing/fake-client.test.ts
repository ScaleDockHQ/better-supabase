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

  it("records every filter operator, write method and paging option", async () => {
    const client = createFakeClient(() => ({ data: [] }));
    const notes = (): ReturnType<typeof client.from> => client.from("notes");

    await notes()
      .select()
      .neq("a", 1)
      .gt("b", 2)
      .gte("c", 3)
      .lt("d", 4)
      .lte("e", 5)
      .like("f", "x%")
      .ilike("g", "y%")
      .is("h", null)
      .contains("i", ["a", "b"])
      .containedBy("j", ["c"])
      .overlaps("k", ["d"])
      .not("l", "eq", 1)
      .or("m.eq.1,n.eq.2")
      .match({ o: 1, p: "q" })
      .order("r", { nullsFirst: true })
      .order("s", { ascending: true, nullsFirst: false })
      .range(10, 19);

    expect(client.requests[0]?.query).toEqual({
      select: "*",
      a: "neq.1",
      b: "gt.2",
      c: "gte.3",
      d: "lt.4",
      e: "lte.5",
      f: "like.x%",
      g: "ilike.y%",
      h: "is.null",
      i: "cs.{a,b}",
      j: "cd.{c}",
      k: "ov.{d}",
      l: "not.eq.1",
      or: "(m.eq.1,n.eq.2)",
      o: "eq.1",
      p: "eq.q",
      order: "r.asc.nullsfirst,s.asc.nullslast",
      offset: "10",
      limit: "10",
    });

    await notes().insert({ a: 1 });
    await notes().upsert({ a: 1 }, { onConflict: "a" });
    await notes().upsert({ a: 2 });
    await notes().update({ a: 3 }).eq("id", 1);
    await notes().delete().eq("id", 1);

    expect(client.requests.slice(1).map((r) => r.method)).toEqual([
      "POST",
      "POST",
      "POST",
      "PATCH",
      "DELETE",
    ]);
    expect(client.requests[2]).toMatchObject({
      prefer: ["resolution=merge-duplicates"],
      query: { on_conflict: "a" },
    });
    expect(client.requests[3]?.query).toEqual({});
  });

  it("sends GET rpc arguments as query parameters", async () => {
    const client = createFakeClient(() => ({ data: 1 }));

    await client.rpc("count_notes", { a: 1 }, { get: true });
    await client.rpc("count_notes", undefined, { head: true });

    expect(client.requests[0]).toMatchObject({
      method: "GET",
      query: { a: "1" },
    });
    expect(client.requests[1]).toMatchObject({ method: "GET", query: {} });
  });

  it("returns a handler error as a failed reply", async () => {
    const client = createFakeClient(() => ({
      error: { code: "23505", message: "duplicate", details: "", hint: "" },
    }));

    const reply = await client.from("notes").insert({ title: "a" });

    expect(reply).toMatchObject({
      data: null,
      error: { code: "23505" },
      status: 400,
    });
  });

  it("refuses single() over several rows with PGRST116", async () => {
    const client = createFakeClient(() => ({ data: [{ id: 1 }, { id: 2 }] }));

    const reply = await client.from("notes").select().single();

    expect(reply).toMatchObject({
      data: null,
      error: { code: "PGRST116" },
      status: 406,
    });
  });

  it("returns the row of maybeSingle() when there is exactly one", async () => {
    const client = createFakeClient(() => ({ data: [{ id: 1 }] }));

    const reply = await client.from("notes").select().maybeSingle();

    expect(reply.data).toEqual({ id: 1 });
  });

  it("counts the rows in the PGRST116 details", async () => {
    const many = createFakeClient(() => ({ data: [{ id: 1 }, { id: 2 }] }));
    const none = createFakeClient(() => ({ data: [] }));

    expect((await many.from("t").select().single()).error?.details).toBe(
      "The result contains 2 rows",
    );
    expect((await none.from("t").select().single()).error?.details).toBe(
      "The result contains 0 rows",
    );
    expect((await many.from("t").select().maybeSingle()).error?.code).toBe(
      "PGRST116",
    );
  });

  it("refuses single() when the handler answers with no data", async () => {
    const client = createFakeClient(() => ({ data: null }));

    expect((await client.from("t").select().single()).error?.code).toBe(
      "PGRST116",
    );
    expect(await client.from("t").select().maybeSingle()).toMatchObject({
      data: null,
      error: null,
    });
  });
});
