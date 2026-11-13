import { describe, expect, it } from "vitest";

import type { PartyLabel } from "../../src/core/party.ts";
import type { RecordRef } from "../../src/schema/types.ts";

import { createPartyResolver, initialsOf } from "../../src/core/party.ts";
import { AsyncResult, ok } from "../../src/core/result.ts";

const label = (refs: readonly RecordRef[]) =>
  AsyncResult.from(() =>
    Promise.resolve(
      ok(
        Object.fromEntries(
          refs.map((ref): [string, PartyLabel] => [
            `${ref.type}:${ref.id}`,
            ref.id === "gone"
              ? { label: ref.id, found: false }
              : {
                  label: `Label ${ref.id}`,
                  url: `/${ref.type}/${ref.id}`,
                  found: true,
                },
          ]),
        ),
      ),
    ),
  );

describe("initialsOf", () => {
  it("takes the first and last word, or two letters of one", () => {
    expect(initialsOf("ada lovelace")).toBe("AL");
    expect(initialsOf("Jean Claude Van Damme")).toBe("JD");
    expect(initialsOf("acme")).toBe("AC");
    expect(initialsOf("  ")).toBe("");
  });
});

describe("createPartyResolver", () => {
  it("prefers a reader's name and avatar and falls back to the label", async () => {
    const asked: (readonly string[])[] = [];

    const parties = createPartyResolver({
      label,
      readers: {
        person: (ids) => {
          asked.push(ids);

          return AsyncResult.from(() =>
            Promise.resolve(
              ok({ p1: { name: "Ada Lovelace", avatarUrl: "/a.png" } }),
            ),
          );
        },
      },
    });

    const found = await parties
      .resolve([
        { type: "person", id: "p1" },
        { type: "person", id: "p1" },
        { type: "person", id: "p2" },
        { type: "company", id: "c1" },
        { type: "company", id: "gone" },
      ])
      .orThrow();

    expect(asked).toEqual([["p1", "p2"]]);

    expect(found["person:p1"]).toEqual({
      type: "person",
      id: "p1",
      name: "Ada Lovelace",
      initials: "AL",
      avatarUrl: "/a.png",
      url: "/person/p1",
      found: true,
    });

    expect(found["person:p2"]?.name).toBe("Label p2");
    expect(found["company:c1"]).not.toHaveProperty("avatarUrl");
    expect(found["company:gone"]).toMatchObject({ name: "gone", found: false });
  });
});
