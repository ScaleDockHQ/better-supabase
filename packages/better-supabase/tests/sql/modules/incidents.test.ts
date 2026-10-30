import { describe, expect, it } from "vitest";

import type { BlockSqlContext } from "../../../src/sql/context.ts";

import { INCIDENTS } from "../../../src/sql/modules/incidents.ts";
import { customContracts, renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const sqlOf = (layout: Layout = {}): string =>
  renderBlocks(["incidents"], layout)
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
    const context = { mode: "custom" } as unknown as BlockSqlContext;
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

  it("keeps postmortem action items as tasks only with the tasks block", () => {
    const without = sqlOf();
    expect(without).not.toContain("incident_postmortem_actions");
    expect(without).not.toContain("add_incident_postmortem_action");
    expect(without).toContain("actionItems must be an array");

    const sql = renderBlocks(["incidents", "tasks"])
      .filter((file) => file.module === "incidents")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain(
      'create table if not exists "better_supabase"."incident_postmortem_actions" (',
    );
    expect(sql).toContain(
      'references "better_supabase"."tasks" ("id") on delete cascade',
    );
    expect(sql).toContain('unique ("postmortem_id", "task_id")');
    expect(sql).toContain('"better_supabase"."create_task"(');
    expect(sql).toContain("actionItems is read-only with the tasks block");
    expect(sql).not.toContain('"action_items" = ');
    // get_incident is language sql, so the list it embeds renders before it.
    expect(
      sql.indexOf('incident_postmortem_action_list"(postmortem_id uuid)'),
    ).toBeLessThan(sql.indexOf('function "better_supabase"."get_incident"'));

    const [contract] = customContracts(["incidents", "tasks"], {
      modules: { incidents: { mode: "custom" } },
    });

    expect(contract?.functions.map((fn) => fn.name)).toEqual(
      expect.arrayContaining([
        "add_incident_postmortem_action",
        "remove_incident_postmortem_action",
      ]),
    );
  });
});
