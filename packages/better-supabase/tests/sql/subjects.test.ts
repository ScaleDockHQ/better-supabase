import { describe, expect, it } from "vitest";

import type { BlockSqlContext } from "../../src/sql/context.ts";
import type { Subject } from "../../src/sql/subjects.ts";

import { subjectReadable } from "../../src/sql/subjects.ts";

const ctx = {
  scope: {
    can: (tenant: string, permission: string) =>
      `can(${tenant}, ${permission})`,
    eq: (left: string, right: string) => `${left} = ${right}`,
  },
  naming: { rename: (name: string) => name },
} as unknown as Pick<BlockSqlContext, "scope" | "naming">;

const args = { type: "t", id: "i", tenant: "o" };

describe("subjectReadable", () => {
  const subjects: [string, Subject][] = [
    ["note", { table: "app.notes", extra: { deletedAt: "deleted_at" } }],
    [
      "draft",
      { table: "app.drafts", tenant: false, extra: { deletedAt: "gone_at" } },
    ],
    ["doc", { table: "app.docs", extra: {} }],
  ];

  it("requires live rows only when asked", () => {
    const live = subjectReadable(ctx, subjects, args, { live: true });
    const any = subjectReadable(ctx, subjects, args);

    expect(live).toContain(`s."deleted_at" is null)`);
    expect(live).toContain(`s."gone_at" is null)`);
    expect(
      live.split("\n").find((line) => line.includes("docs")),
    ).not.toContain("is null");
    expect(any).not.toContain("is null");
  });

  it("reads every subject when there are none to check", () => {
    expect(subjectReadable(ctx, [], args, { live: true })).toBe("true");
  });
});
