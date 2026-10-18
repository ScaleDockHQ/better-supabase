import { describe, expect, test } from "vitest";

import { groupFollowers } from "../../../../features/create/components/canvas-drag";

const positions = new Map([
  ["group:teams", { x: 0, y: 0 }],
  ["public.teams", { x: 16, y: 40 }],
  ["public.members", { x: 300, y: 40 }],
  ["public.profiles", { x: 600, y: 0 }],
]);

const groups = [
  { id: "group:teams", members: ["public.teams", "public.members"] },
];

describe("groupFollowers", () => {
  test("a group drag moves its tables by the same offset", () => {
    expect(
      groupFollowers(
        [{ type: "position", id: "group:teams", position: { x: 20, y: -10 } }],
        positions,
        groups,
      ),
    ).toEqual([
      { type: "position", id: "public.teams", position: { x: 36, y: 30 } },
      { type: "position", id: "public.members", position: { x: 320, y: 30 } },
    ]);
  });

  test("a table drag and a selection move nothing else", () => {
    expect(
      groupFollowers(
        [
          {
            type: "position",
            id: "public.profiles",
            position: { x: 640, y: 0 },
          },
          { type: "select", id: "group:teams", selected: true },
        ],
        positions,
        groups,
      ),
    ).toEqual([]);
  });
});
