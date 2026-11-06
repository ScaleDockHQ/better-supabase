import { describe, expect, it } from "vitest";

import { SQL_MODULES } from "../../../src/sql/registry.ts";
import { renderBlocks } from "../../../src/sql/render.ts";

const all = renderBlocks(Object.keys(SQL_MODULES), {});

const schema = (module: string): string =>
  all.find((file) => file.module === module && file.kind === "schema")!
    .contents;

const data = (module: string): string =>
  all.find((file) => file.module === module && file.kind === "data")!.contents;

describe("generation-time choices", () => {
  it("writes no do block that creates objects in any schema file", () => {
    const offenders = all
      .filter(
        (file) =>
          file.kind === "schema" &&
          /to_regclass\('(?:realtime|storage)\.|exception when duplicate_object/.test(
            file.contents,
          ),
      )
      .map((file) => file.path);

    expect(offenders).toEqual([]);
  });

  it("enables row level security on each World table without a loop", () => {
    const sql = schema("workflow-sdk");

    expect(sql).toContain(
      "alter table workflow.workflow_runs enable row level security;",
    );
    expect(sql).toContain(
      "grant all on workflow.workflow_run_keys to service_role;",
    );
    expect(sql).not.toContain("execute format('alter table workflow");
    expect(data("workflow-sdk")).toContain("timestamp without time zone");
  });

  it("keeps the inbox team move and the flag context upgrade out of the schema file", () => {
    expect(schema("teams")).not.toContain("shared_teams");
    expect(schema("teams")).toContain("conversations_team_fkey");
    expect(schema("flags")).not.toContain("v_name name");
    expect(SQL_MODULES["teams"]!.upgrades?.map((step) => step.from)).toContain(
      2,
    );
    expect(
      SQL_MODULES["flags"]!.upgrades?.find((step) => step.from === 2)?.sql,
    ).toBeTypeOf("function");
  });

  it("has one owner for the node JSON and the chat share functions", () => {
    const owners = (name: string) =>
      all
        .filter(
          (file) =>
            file.kind === "schema" &&
            file.contents.includes(
              `create or replace function "better_supabase"."${name}"(`,
            ),
        )
        .map((file) => file.module);

    expect(owners("drive_node_json")).toEqual(["drive-files"]);
    expect(owners("share_ai_chat")).toEqual(["share-links"]);
  });

  it("keeps the number-key restore in the legal entities data file", () => {
    const sql = renderBlocks(["invoices", "legal-entities"], {}).find(
      (file) => file.module === "legal-entities" && file.kind === "data",
    )!.contents;

    expect(sql).toContain("LEGAL_ENTITIES_DISABLE_COLLISION");
  });
});
