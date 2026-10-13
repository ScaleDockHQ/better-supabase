import { describe, expect, it } from "vitest";

import * as client from "../../../../src/blocks/search/react/index.ts";
import * as server from "../../../../src/blocks/search/react/server.ts";

const hit = (subjectType: string, subjectId: string) => ({
  organizationId: "org",
  subjectType,
  subjectId,
  title: subjectId,
  url: null,
  snippet: null,
  score: 1,
});

describe("search react-server build", () => {
  it("exports the same names as the client build", () => {
    expect(Object.keys(server).toSorted()).toEqual(
      Object.keys(client).toSorted(),
    );
  });

  it("throws from useCommandSearch", () => {
    expect(() => server.useCommandSearch()).toThrow(
      "useCommandSearch() runs in Client Components only",
    );
  });
});

describe("groupHits", () => {
  it("groups hits by subject type in the order they rank", () => {
    const groups = server.groupHits([
      hit("deal", "d1"),
      hit("note", "n1"),
      hit("deal", "d2"),
    ]);
    expect(
      groups.map((group) => [
        group.key,
        group.items.map((item) => item.subjectId),
      ]),
    ).toEqual([
      ["deal", ["d1", "d2"]],
      ["note", ["n1"]],
    ]);
    expect(server.groupHits([])).toEqual([]);
  });
});
