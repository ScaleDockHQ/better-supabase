import { describe, expect, it } from "vitest";

import { createFakeClient } from "../../src/testing/fake-client.ts";

function last(
  build: (client: ReturnType<typeof createFakeClient>) => PromiseLike<unknown>,
) {
  const client = createFakeClient(() => ({ data: [] }));

  return build(client).then(() => client.requests.at(-1)!.query);
}

describe("fake client filters", () => {
  it("keeps both bounds of a range on one column", async () => {
    const query = await last((c) =>
      c.from("t").select().gte("price", 1).lte("price", 5),
    );

    expect(query["and"]).toBe("(price.gte.1,price.lte.5)");
    expect(query["price"]).toBeUndefined();
  });

  it("keeps a third filter on the same column", async () => {
    const query = await last((c) =>
      c.from("t").gt("n", 1).lt("n", 9).neq("n", 5),
    );

    expect(query["and"]).toBe("(n.gt.1,n.lt.9,n.neq.5)");
  });

  it("keeps two or groups", async () => {
    const query = await last((c) =>
      c.from("t").or("a.eq.1,b.eq.2").or("c.eq.3,d.eq.4"),
    );

    expect(query["and"]).toBe("(or(a.eq.1,b.eq.2),or(c.eq.3,d.eq.4))");
  });

  it("quotes list items that hold a comma and writes jsonb containment", async () => {
    const query = await last((c) =>
      c.from("t").in("name", ["a,b", "c"]).contains("meta", { k: 1 }),
    );

    expect(query["name"]).toBe('in.("a,b",c)');
    expect(query["meta"]).toBe('cs.{"k":1}');
  });

  it("records the search, range and pattern operators", async () => {
    const query = await last((c) =>
      c
        .from("t")
        .textSearch("body", "cat", { type: "websearch", config: "english" })
        .rangeGt("r", "[1,2)")
        .likeAnyOf("s", ["a%", "b%"])
        .isDistinct("z", 1),
    );

    expect(query).toMatchObject({
      body: "wfts(english).cat",
      r: "sr.[1,2)",
      s: "like(any).{a%,b%}",
      z: "isdistinct.1",
    });
  });
});
