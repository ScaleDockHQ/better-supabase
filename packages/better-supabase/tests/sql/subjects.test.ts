import { describe, expect, it } from "vitest";

import type { BlockSqlContext } from "../../src/sql/context.ts";
import type { Subject } from "../../src/sql/subjects.ts";

import { subjectReadable, subjectRowReadable } from "../../src/sql/subjects.ts";

const ctx = {
  scope: {
    can: (tenant: string, permission: string) =>
      `can(${tenant}, ${permission})`,
    eq: (left: string, right: string) => `${left} = ${right}`,
  },
  naming: { rename: (name: string) => name },
  can: (scope: string, id: string, permission: string) =>
    `can_on(${scope}, ${id}, ${permission})`,
  providerRowsWith: "authz.rows_with({resource}, {permission}, {ids})",
} as unknown as Pick<
  BlockSqlContext,
  "scope" | "naming" | "can" | "providerRowsWith"
>;

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

describe("subjectReadable with a registered read granted per row or to an owner", () => {
  const rows: Subject = {
    table: "app.files",
    idType: "uuid",
    permission: "file.read",
    read: { entry: { key: "file.read", rows: "file_node" }, scope: "project" },
    extra: {},
  };

  const owned: Subject = {
    table: "app.notes",
    read: { entry: { owner: "owner_id" } },
    extra: {},
  };

  it("checks the key, the provider's row grants and the scope on the row", () => {
    const sql = subjectReadable(ctx, [["file", rows]], args);

    expect(sql).toContain(
      `(can(o, 'file.read') or can_on(project, s."id"::text, 'file.read') or s."id"::text in (select r.id::text from authz.rows_with(file_node, 'file.read', array[s."id"::text]) as r(id)))`,
    );
    expect(sql).not.toMatch(/\) and can\(o/u);
  });

  it("lets the owner column grant a read without a key", () => {
    expect(subjectReadable(ctx, [["note", owned]], args)).toContain(
      `and s."owner_id" = auth.uid())`,
    );
  });

  it("needs the provider's rowsWith for a row grant", () => {
    expect(() =>
      subjectReadable(
        { ...ctx, providerRowsWith: undefined },
        [["file", rows]],
        args,
      ),
    ).toThrow(/records\.file\.permissions\.read\.rows needs/u);
  });

  it("requires the also key with the other grants", () => {
    const sql = subjectReadable(
      ctx,
      [
        [
          "note",
          {
            table: "app.notes",
            read: { entry: { owner: "owner_id", also: "notes.read" } },
            extra: {},
          },
        ],
      ],
      args,
    );

    expect(sql).toContain(
      `and ((can(o, 'notes.read')) and s."owner_id" = auth.uid()))`,
    );
  });
});

describe("subjectRowReadable", () => {
  const withSubjects = (installed: boolean) =>
    ({
      installed: (name: string) => installed && name === "subjects",
      of: () => ({ fn: (name: string) => `bsb.${name}` }),
    }) as unknown as Pick<BlockSqlContext, "installed" | "of">;

  it("asks can_subject for the row's type and id", () => {
    expect(subjectRowReadable(withSubjects(true), "c")).toBe(
      `coalesce(bsb.can_subject(c."subject_type", c."subject_id"::text, 'read'), false)`,
    );
    expect(
      subjectRowReadable(withSubjects(true), "c", {
        type: "record_type",
        id: "record_id",
      }),
    ).toBe(
      `coalesce(bsb.can_subject(c."record_type", c."record_id"::text, 'read'), false)`,
    );
  });

  it("needs the subjects block", () => {
    expect(() => subjectRowReadable(withSubjects(false), "c")).toThrow(
      /needs the subjects block/u,
    );
  });
});
