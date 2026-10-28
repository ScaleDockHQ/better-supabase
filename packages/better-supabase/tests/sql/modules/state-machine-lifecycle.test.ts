import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { workflowOf } from "../../../src/sql/modules/state-machine-lifecycle.ts";
import { renderBlocks } from "../../../src/sql/render.ts";

const sqlOf = (
  modules: AnyBlocksConfig,
  installed: readonly string[] = ["workflow-editor"],
): string =>
  renderBlocks([...installed, "state-machine"], { modules })
    .filter((file) => file.module === "state-machine")
    .map((file) => file.contents)
    .join("\n");

const machine = (extra: Record<string, unknown> = {}): AnyBlocksConfig => ({
  "state-machine": {
    options: {
      machines: {
        deal: {
          table: "public.deals",
          column: "stage",
          workflow: "deal-stages",
          ...extra,
        },
      },
    },
  },
});

describe("workflow-driven lifecycle", () => {
  it("pins the published version and checks edges against its graph", () => {
    const sql = sqlOf(machine({ stages: true }));

    expect(sql).toContain(
      'add column if not exists "workflow_version_id" uuid references "better_supabase"."workflow_versions"',
    );
    expect(sql).toContain('function "better_supabase"."lifecycle_graph"');
    expect(sql).toContain("STATE_LIFECYCLE_UNPUBLISHED");
    expect(sql).toContain("d.\"slug\" = 'deal-stages'");
    expect(sql).toContain("-> 'transitions' -> old.\"stage\"::text");
    expect(sql).toContain("'workflowVersionId'");
    expect(sql).toContain("v_order text[];");
    expect(sql).toContain("status_stages");
  });

  it("leaves static machines unchanged", () => {
    const sql = sqlOf({
      "state-machine": {
        options: {
          machines: {
            quote: {
              table: "public.quotes",
              column: "status",
              initial: "draft",
              transitions: { draft: ["sent"] },
            },
          },
        },
      },
    });

    expect(sql).not.toContain("lifecycle_graph");
    expect(sql).not.toContain("workflow_version_id");
  });

  it("needs the workflow-editor module", () => {
    expect(() => sqlOf(machine(), [])).toThrow(
      "machines.deal.workflow needs the workflow-editor module",
    );
  });

  it("needs the lifecycles table's workflow column", () => {
    expect(() =>
      sqlOf({
        ...machine(),
        "state-machine": {
          ...machine()["state-machine"],
          columns: { lifecycles: { workflowVersion: null } },
        },
      }),
    ).toThrow("needs the lifecycles table's workflowVersion column");
  });

  it.each([
    [{ workflow: 1 }, "must be a workflow definition slug"],
    [{ workflow: "Bad Slug" }, "must be a workflow definition slug"],
    [{ workflow: "deal-stages", initial: "new" }, "leave out initial"],
    [{ workflow: "deal-stages", transitions: {} }, "leave out transitions"],
    [{ workflow: "deal-stages", order: [] }, "leave out order"],
    [{ workflow: "deal-stages", version: 2 }, "leave out version"],
    [
      { workflow: "deal-stages", requiresApproval: {} },
      "leave out requiresApproval",
    ],
    [{ workflow: "deal-stages", lifecycle: false }, "keeps a lifecycle row"],
  ])("rejects %j", (record, message) => {
    expect(() => workflowOf(record, "m")).toThrow(message);
  });

  it("reads no workflow when unset", () => {
    expect(workflowOf({}, "m")).toBeUndefined();
    expect(workflowOf({ workflow: "deal-stages", lifecycle: true }, "m")).toBe(
      "deal-stages",
    );
  });
});
