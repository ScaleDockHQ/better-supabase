import { describe, expect, it } from "vitest";

import type { BlockSqlContext } from "../../src/sql/context.ts";
import type { Subject } from "../../src/sql/subjects.ts";

import { renderBlocks } from "../../src/sql/render.ts";
import {
  subjectIdMatches,
  subjectReadable,
  subjectRowReadable,
} from "../../src/sql/subjects.ts";

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

describe("subjectIdMatches", () => {
  it("casts the value to the id column's type", () => {
    expect(subjectIdMatches({ table: "t", extra: {} }, "$1")).toBe(
      's."id"::text = $1',
    );
    expect(
      subjectIdMatches(
        { table: "t", id: "key", idType: "text", extra: {} },
        "$1",
      ),
    ).toBe('s."key" = ($1)::text');
  });

  it("guards an inferred uuid or integer id against values that do not cast", () => {
    expect(
      subjectIdMatches(
        { table: "t", idType: "uuid", idInferred: true, extra: {} },
        "$1",
      ),
    ).toContain("case when $1 ~* '^[0-9a-f]{8}-");
    expect(
      subjectIdMatches(
        { table: "t", idType: "bigint", idInferred: true, extra: {} },
        "$1",
      ),
    ).toBe(
      "s.\"id\" = (case when $1 ~ '^-?[0-9]{1,18}$' then ($1)::bigint end)",
    );
    expect(
      subjectIdMatches(
        { table: "t", idType: "integer", idInferred: true, extra: {} },
        "$1",
      ),
    ).toContain("{1,9}$' then ($1)::integer");
    expect(
      subjectIdMatches(
        { table: "t", idType: "smallint", idInferred: true, extra: {} },
        "$1",
      ),
    ).toContain("{1,4}$' then ($1)::smallint");
  });
});

describe("blocks.<instance>.on errors", () => {
  const subjects = {
    order: { table: "public.orders" },
    note: { table: "public.notes", tenant: false as const },
  };

  const render = (module: string, on: unknown): unknown =>
    renderBlocks([module], {
      subjects,
      modules: { [module]: { on } } as never,
    });

  it.each([
    [
      "tags",
      [],
      /blocks\.tags\.on: list at least one config\.recordTypes type/u,
    ],
    [
      "tags",
      ["nope"],
      /"nope" is not a subject type in config\.recordTypes\. Types: order, note/u,
    ],
    ["tags", 3, /blocks\.tags\.on: pass a list of config\.recordTypes types/u],
    ["tags", { Bad: { table: "x" } }, /"Bad" must be lowercase letters/u],
    [
      "tags",
      { order: { table: "x", foo: 1 } },
      /on\.order\.foo is not an option\. Options: table, id/u,
    ],
    ["tags", { order: { table: 3 } }, /blocks\.tags\.on\.order needs a table/u],
    [
      "tags",
      { order: { idType: "1" } },
      /on\.order\.idType must be a type name/u,
    ],
    [
      "tags",
      { order: { id: 3 } },
      /blocks\.tags\.on\.order\.id must be a string/u,
    ],
    [
      "tags",
      { order: { cascade: "y" } },
      /on\.order\.cascade must be true or false/u,
    ],
    ["relations", { note: {} }, /on\.note\.tenant can't be false/u],
    [
      "attachments",
      { order: { permissions: 3 } },
      /on\.order\.permissions must be \{ read\?, upload\?, manage\? \}/u,
    ],
    [
      "attachments",
      { order: { permissions: { nope: "a" } } },
      /permissions\.nope: use read, upload and manage with a permission key/u,
    ],
    [
      "attachments",
      { order: { scope: 3 } },
      /on\.order\.scope must be the name of a provider scope/u,
    ],
    [
      "attachments",
      { order: { scope: "x" } },
      /on\.order\.scope needs blocks\.permissions\.model "provider"/u,
    ],
  ])("%s rejects on %j", (module, on, message) => {
    expect(() => render(module, on)).toThrow(message);
  });

  it.each([
    [3, /on\.order\.links needs \{ table, subject, tag \}/u],
    [
      { table: "a.b.c" },
      /on\.order\.links\.table must be "table" or "schema\.table"/u,
    ],
    [
      { table: "Bad" },
      /on\.order\.links\.table must be "table" or "schema\.table"/u,
    ],
    [
      { table: "order_tags", nope: "x" },
      /links\.nope is not a column\. Columns: subject, tag, tenant, createdAt/u,
    ],
    [
      { table: "order_tags" },
      /on\.order\.links\.subject must be a column name/u,
    ],
    [
      { table: "order_tags", subject: "order_id", tag: "tag_id", tenant: 3 },
      /on\.order\.links\.tenant must be a column name/u,
    ],
  ])("tags rejects the link table %j", (links, message) => {
    expect(() => render("tags", { order: { links } })).toThrow(message);
  });

  it("writes tags straight into a bound link table", () => {
    const sql = renderBlocks(["tags"], {
      subjects,
      modules: {
        tags: {
          on: {
            order: {
              links: {
                table: "order_tags",
                subject: "order_id",
                tag: "tag_id",
              },
            },
          },
        },
      },
    })
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain(
      'insert into "public"."order_tags" ("order_id", "tag_id")',
    );
    expect(sql).toContain(
      'delete from "public"."order_tags" l where l."order_id"::text = untag.subject_id',
    );
  });
});
