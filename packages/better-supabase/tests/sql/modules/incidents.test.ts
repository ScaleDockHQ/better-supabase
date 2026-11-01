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
    expect(without).not.toContain(
      'function "better_supabase"."add_incident_postmortem_action"',
    );
    expect(without).not.toContain("action_items");

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
    expect(sql).toContain("actionItems was removed");
    expect(sql).not.toContain("action_items");
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

  describe("regulatory reporting", () => {
    const withReminders = (): string =>
      renderBlocks(["incidents", "reminders"], {})
        .filter((file) => file.module === "incidents")
        .map((file) => file.contents)
        .join("\n");

    it("creates the profile and filing tables and the functions", () => {
      const sql = sqlOf();

      expect(sql).toContain("incident_regulatory_profiles");
      expect(sql).toContain("incident_regulatory_filings");
      expect(sql).toContain("save_incident_regulatory_profile");
      expect(sql).toContain("submit_incident_filing");
      expect(sql).toContain("interval '24 hours'");
      expect(sql).toContain("interval '72 hours'");
      expect(sql).toContain("interval '1 month'");
      expect(sql).toContain("interval '14 days'");
      expect(sql).toContain("interval '4 hours'");
    });

    it("keeps the planner internal to the service role", () => {
      const grants = sqlOf()
        .split("\n")
        .filter((line) => line.includes('"plan_incident_filings"'))
        .filter((line) => line.startsWith("grant execute"));

      expect(grants).toHaveLength(1);
      expect(grants[0]).toContain("to service_role");
      expect(grants[0]).not.toContain("authenticated");
    });

    it("writes reminders only with the reminders block", () => {
      expect(sqlOf()).not.toContain("remind_at");
      expect(withReminders()).toMatch(/insert into "[a-z_]+"\."reminders"/);
    });

    it("bumps the version with an upgrade from 3", () => {
      expect(INCIDENTS.version).toBe(4);
      expect(INCIDENTS.upgrades?.some((step) => step.from === 3)).toBe(true);
    });
  });
});
