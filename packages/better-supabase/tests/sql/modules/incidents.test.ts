import { describe, expect, it } from "vitest";

import type { ModuleContext } from "../../../src/sql/context.ts";

import { INCIDENTS } from "../../../src/sql/modules/incidents.ts";
import { customContracts, renderModules } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderModules>[1];

const sqlOf = (layout: Layout = {}): string =>
  renderModules(["incidents"], layout)
    .filter((file) => file.module === "incidents")
    .map((file) => file.contents)
    .join("\n");

describe("incidents module", () => {
  it("grants the public status page to anon through one function", () => {
    const sql = sqlOf();

    const anonGrants = sql
      .split("\n")
      .filter(
        (line) =>
          line.startsWith("grant execute") &&
          line.includes("anon") &&
          !line.includes("actor_"),
      );

    expect(anonGrants).toEqual([
      `grant execute on function "better_supabase"."public_status_page"(text, integer) to anon, authenticated, service_role;`,
    ]);
    expect(sql).not.toMatch(/create policy [^\n]* to anon/);
  });

  it("renders nothing in custom mode and lists the functions to implement", () => {
    const custom: Layout = { modules: { incidents: { mode: "custom" } } };
    expect(sqlOf(custom).trim()).toBe("");
    // SAFETY: custom mode returns before reading anything else on the context.
    const context = { mode: "custom" } as unknown as ModuleContext;
    expect(INCIDENTS.build(context, {})).toBe("");
    const [contract] = customContracts(["incidents"], custom);
    expect(contract?.functions.map((fn) => fn.name)).toEqual(
      expect.arrayContaining([
        "open_incident",
        "post_incident_update",
        "public_status_page",
      ]),
    );
  });
});
