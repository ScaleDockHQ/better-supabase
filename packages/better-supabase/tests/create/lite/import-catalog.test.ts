import { describe, expect, it } from "vitest";

import type {
  RawCatalog,
  RawColumn,
  RawConstraint,
  RawTable,
} from "../../../src/create/lite/catalog.ts";

import { designFromCatalog } from "../../../src/create/lite/import.ts";

const column = (
  name: string,
  type: string,
  rest: Partial<RawColumn> = {},
): RawColumn => ({
  name,
  type,
  nullable: true,
  default: null,
  identity: null,
  generated: false,
  comment: null,
  udt: type,
  array: false,
  enumValues: [],
  ...rest,
});

const key = (columns: string[] = ["id"]): RawConstraint => ({
  name: "pk",
  type: "p",
  columns,
  refSchema: null,
  refTable: null,
  refColumns: null,
  onDelete: null,
});

const table = (name: string, rest: Partial<RawTable> = {}): RawTable => ({
  schema: "public",
  name,
  kind: "r",
  rls: true,
  comment: null,
  columns: [column("id", "uuid", { nullable: false })],
  constraints: [key()],
  indexes: [],
  policies: 1,
  triggers: 0,
  ...rest,
});

const foreign = (
  columns: string[],
  refTable: string,
  rest: Partial<RawConstraint> = {},
): RawConstraint => ({
  name: `fk_${columns.join("_")}`,
  type: "f",
  columns,
  refSchema: "public",
  refTable,
  refColumns: ["id"],
  onDelete: null,
  ...rest,
});

const run = (tables: RawTable[], functions: string[] = []) =>
  designFromCatalog({ tables, functions } satisfies RawCatalog);

describe("designFromCatalog edge cases", () => {
  it("keeps tables without a usable id key as they are", () => {
    const { design, report } = run([
      table("composite", { constraints: [key(["a", "b"])] }),
      table("keyless", { constraints: [] }),
      table("named", { constraints: [key(["code"])] }),
      table("serial", { columns: [column("id", "integer")] }),
      table("other", { schema: "audit" }),
      table("good"),
    ]);

    expect(Object.keys(design.appTables ?? {})).toEqual(["good"]);
    expect(report.preserved.map((each) => each.reason)).toEqual(
      expect.arrayContaining([
        "It has no single uuid or bigint id key, so it is kept as it is.",
        "Only the public schema is modeled.",
      ]),
    );
  });

  it("maps delete actions, unique keys and reference targets", () => {
    const { design, report } = run([
      table("parent"),
      table("child", {
        columns: [
          column("id", "uuid", { nullable: false }),
          column("a", "uuid"),
          column("b", "uuid"),
          column("c", "uuid"),
          column("d", "uuid"),
          column("e", "uuid"),
          column("f", "uuid"),
          column("g", "uuid"),
        ],
        constraints: [
          key(),
          foreign(["a"], "parent", { onDelete: "r" }),
          foreign(["b"], "parent", { onDelete: "c" }),
          foreign(["c"], "parent", { onDelete: "n" }),
          foreign(["d"], "parent", { onDelete: "d" }),
          foreign(["e"], "missing"),
          foreign(["f"], "parent", { refColumns: ["code"] }),
          foreign(["f", "g"], "parent"),
          { ...foreign(["g"], "users"), refSchema: "auth", onDelete: "c" },
          { ...key(["a"]), type: "u" },
          { ...key(["b", "c"]), type: "u" },
        ],
      }),
    ]);

    const columns = design.appTables?.["child"]?.columns;

    expect(columns?.["a"]).toMatchObject({
      unique: true,
      references: { table: "parent", onDelete: "restrict" },
    });
    expect(columns?.["b"]?.references?.onDelete).toBe("cascade");
    expect(columns?.["c"]?.references?.onDelete).toBe("set null");
    expect(columns?.["d"]?.references?.onDelete).toBe("no action");
    expect(columns?.["g"]?.references).toEqual({
      table: "auth.users",
      onDelete: "cascade",
    });
    expect(design.appTables?.["child"]?.unique).toEqual([["b", "c"]]);
    expect(
      report.preserved.filter((each) => each.kind === "foreign_key"),
    ).toHaveLength(3);
  });

  it("models defaults, identity, comments, timestamps and bigint ids", () => {
    const { design, report } = run([
      table("events", {
        comment: "All events",
        columns: [
          column("id", "bigint", { nullable: false }),
          column("created_at", "timestamp with time zone"),
          column("label", "character varying(20)", {
            nullable: false,
            default: "'x'::character varying",
            comment: "Shown label",
          }),
          column("count", "integer", { default: "(0)::integer" }),
          column("bad", "integer", { default: "gen_random_uuid()" }),
          column("seq", "bigint", { identity: "d" }),
          column("made", "text", { generated: true }),
          column("span", "interval"),
        ],
        indexes: [
          { columns: ["label"], plain: true },
          { columns: ["missing"], plain: true },
          { columns: ["label"], plain: false },
        ],
      }),
    ]);

    const events = design.appTables?.["events"];

    expect(events).toMatchObject({
      id: "bigint",
      timestamps: false,
      comment: "All events",
      indexes: [["label"]],
    });
    expect(events?.columns?.["label"]).toMatchObject({
      default: "'x'",
      nullable: false,
      comment: "Shown label",
    });
    expect(events?.columns?.["seq"]?.identity).toBe(true);
    expect(events?.columns?.["bad"]?.default).toBeUndefined();
    expect(report.preserved.map((each) => each.kind)).toEqual(
      expect.arrayContaining(["default", "column", "index"]),
    );
  });

  it("reports views, block tables, triggers, policies and functions", () => {
    const { design, report } = run(
      [
        table("v", { kind: "v" }),
        table("bsb_internal"),
        table("open", { rls: false, triggers: 2, policies: 0 }),
        table("locked", { policies: 0 }),
        table("guarded", { policies: 2 }),
        table("single", { policies: 1 }),
      ],
      ["public.touch"],
    );

    expect(report.blockOwned).toEqual(["public.bsb_internal"]);
    expect(report.tables.map((each) => each.rung)).toEqual([
      "open",
      "locked",
      "protected",
      "protected",
    ]);
    expect(report.issues.map((each) => each.code)).toEqual([
      "verify_rls_disabled",
      "verify_no_policies",
    ]);
    expect(report.preserved.map((each) => each.reason)).toEqual(
      expect.arrayContaining([
        "2 trigger(s) are kept as they are.",
        "2 policies are kept as they are.",
        "1 policy is kept as it is.",
        "A function is kept as it is.",
      ]),
    );
    expect(Object.keys(design.appTables ?? {})).toHaveLength(4);
  });

  it("returns an empty design when nothing can be modeled", () => {
    expect(run([table("bsb_x")]).design).toEqual({});
  });
});
