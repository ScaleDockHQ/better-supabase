import { describe, expect, it } from "vitest";

import type { BlockSqlContext } from "../../../src/sql/context.ts";

import { COMPLIANCE } from "../../../src/sql/modules/compliance.ts";
import { customContracts, renderBlocks } from "../../../src/sql/render.ts";
import { ownTablesOf } from "../../fixtures/own-tables.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const BASE = ["versions", "attachments", "notifications", "compliance"];

const sqlOf = (
  layout: Layout = {},
  modules: readonly string[] = BASE,
): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === "compliance")
    .map((file) => file.contents)
    .join("\n");

describe("compliance module", () => {
  it("links evidence to an attachment only when attachments owns its table", () => {
    const sql = sqlOf();
    expect(sql).toMatch(
      /"attachment_id" uuid references "better_supabase"\."attachments"/,
    );
    expect(sql).toContain("the attachment isn''t a file in this organization");

    const bare = sqlOf({}, ["versions", "compliance"]);
    expect(bare).not.toMatch(/"attachment_id" uuid references/);
    expect(bare).toContain("evidence files need the attachments module");

    const custom = sqlOf({ modules: { attachments: { mode: "custom" } } });
    expect(custom).toContain("evidence files need the attachments module");
  });

  it("notifies the assignee of a missed task only with notifications installed", () => {
    expect(sqlOf()).toContain("'evidence_task.missed:'");
    expect(sqlOf({}, ["versions", "compliance"])).not.toContain(
      "'evidence_task.missed:'",
    );
  });

  it("references the policy version only when versions owns its table", () => {
    expect(sqlOf()).toMatch(
      /references "better_supabase"\."versions" \("id"\) on delete restrict/,
    );

    const modules = { versions: { tables: { versions: "app.revisions" } } };
    const overApp = sqlOf({ modules, ownTables: ownTablesOf(modules) });

    expect(overApp).not.toContain("on delete restrict");
  });

  it("refuses to build on versions in custom mode", () => {
    expect(() => sqlOf({ modules: { versions: { mode: "custom" } } })).toThrow(
      "blocks.compliance needs the versions tables",
    );
  });

  it("renders nothing in custom mode and lists the functions to implement", () => {
    const custom: Layout = { modules: { compliance: { mode: "custom" } } };
    expect(sqlOf(custom).trim()).toBe("");
    // SAFETY: custom mode returns before reading anything else on the context.
    const context = { mode: "custom" } as unknown as BlockSqlContext;
    expect(COMPLIANCE.build(context, {})).toBe("");
    const [contract] = customContracts(["compliance"], custom);
    expect(contract?.functions.map((fn) => fn.name)).toEqual(
      expect.arrayContaining([
        "save_control",
        "control_posture",
        "acknowledge_policy",
      ]),
    );
  });

  it("keeps a framework's kind and a control's source and jurisdiction", () => {
    const sql = sqlOf();
    expect(sql).toContain(
      `"kind" text not null default 'standard' check ("kind" in ('standard', 'legal', 'internal', 'contract'))`,
    );
    expect(sql).toContain(
      `alter table "better_supabase"."controls" add column if not exists "source" text check ("source" is null or length("source") between 1 and 200);`,
    );
    expect(sql).toContain(
      `add column if not exists "jurisdiction" text check ("jurisdiction" is null or length("jurisdiction") between 1 and 200);`,
    );
    expect(sql).toContain(
      `drop function if exists "better_supabase"."save_control_framework"(uuid, text, text, text, text);`,
    );
    expect(sql).toContain(
      `drop function if exists "better_supabase"."save_control"(uuid, text, text, text, uuid, boolean, uuid);`,
    );
    expect(sql).toContain(
      "kind must be one of standard, legal, internal, contract",
    );
  });
});
