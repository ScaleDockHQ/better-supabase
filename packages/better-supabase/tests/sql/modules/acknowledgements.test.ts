import { describe, expect, it } from "vitest";

import { customContracts, renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const sqlOf = (modules: readonly string[], layout: Layout = {}): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === "acknowledgements")
    .map((file) => file.contents)
    .join("\n");

const BASE = ["versions", "acknowledgements"];

describe("acknowledgements module", () => {
  it("keeps acknowledgements bound to a version and assignments per principal", () => {
    const sql = sqlOf(BASE);

    for (const table of [
      "acknowledgement_assignments",
      "acknowledgements",
      "acknowledgement_notices",
    ]) {
      expect(sql).toContain(
        `create table if not exists "better_supabase"."${table}"`,
      );
    }

    expect(sql).toContain(
      `references "better_supabase"."versions" ("id") on delete restrict`,
    );
    expect(sql).toContain(
      "check (\"principal_type\" in ('user', 'team', 'role'))",
    );
    expect(sql).toContain(
      `"better_supabase"."current_acknowledgement_version"(`,
    );
    expect(sql).toContain("ACKNOWLEDGEMENT_VERSION_STALE");
    expect(sql).toContain(
      `revoke execute on function "better_supabase"."current_acknowledgement_version"(uuid, text, text) from public, anon, authenticated;`,
    );
  });

  it("assigns teams and checks signatures only when those modules are installed", () => {
    const base = sqlOf(BASE);
    expect(base).toContain("team assignments need the teams module");
    expect(base).toContain(
      "acknowledging with a signature needs the signatures module",
    );

    const teams = sqlOf(["teams", ...BASE]);
    expect(teams).toContain(`from "better_supabase"."team_members" tm`);

    const signatures = sqlOf(["signatures", ...BASE]);
    expect(signatures).toContain(`from "better_supabase"."signatures" sg`);
    expect(signatures).toContain("'completed'");
  });

  it("notifies the overdue once per version through notifications", () => {
    expect(sqlOf(BASE)).not.toContain("'type', 'acknowledgement.reminded'");
    const notified = sqlOf(["notifications", ...BASE]);
    expect(notified).toContain("'type', 'acknowledgement.reminded'");
    expect(notified).toContain(`"better_supabase"."acknowledgement_notices"`);
  });

  it("reads a record's version column from on.<type>.versionColumn", () => {
    const layout: Layout = {
      modules: {
        acknowledgements: {
          on: {
            policy: { table: "public.policies", versionColumn: "version_id" },
          },
        },
      },
    };

    const sql = sqlOf(BASE, layout);
    expect(sql).toContain(
      `select s."version_id"::uuid from "public"."policies" s`,
    );
    expect(sql).toContain("ACKNOWLEDGEMENT_SUBJECT_UNSUPPORTED");

    expect(() =>
      sqlOf(BASE, {
        modules: {
          acknowledgements: {
            on: { policy: { table: "public.policies", versionColumn: "Bad" } },
          },
        },
      }),
    ).toThrow(/versionColumn must be a column name/u);
  });

  it("needs a versions table", () => {
    expect(() =>
      sqlOf(BASE, { modules: { versions: { mode: "custom" } } }),
    ).toThrow(/versions can't be in custom mode/u);
  });

  it("renders nothing in custom mode and lists the functions to implement", () => {
    const custom: Layout = {
      modules: { acknowledgements: { mode: "custom" } },
    };

    expect(sqlOf(BASE, custom).trim()).toBe("");
    const [contract] = customContracts(["acknowledgements"], custom);
    expect(contract?.functions.map((fn) => fn.name)).toEqual([
      "assign_acknowledgement",
      "unassign_acknowledgement",
      "list_acknowledgement_assignments",
      "acknowledge",
      "list_my_acknowledgements",
      "acknowledgement_status",
      "acknowledgements_of",
      "notify_due_acknowledgements",
    ]);
  });

  it("works on the app's tables without creating them", () => {
    const sql = sqlOf(BASE, {
      modules: {
        acknowledgements: {
          tables: {
            assignments: "app.read_requests",
            acknowledgements: "app.read_receipts",
          },
        },
      },
      ownTables: {
        "app.read_requests": "app.sql",
        "app.read_receipts": "app.sql",
      },
    });

    expect(sql).not.toMatch(/create table if not exists "app"/u);
    expect(sql).toContain(`"app"."read_requests"`);
    expect(sql).toContain(`"app"."read_receipts"`);
    expect(sql).toContain(`"bsb_read_receipts_`);
  });
});
