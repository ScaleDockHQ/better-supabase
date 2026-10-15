import { describe, expect, it } from "vitest";

import type { CatalogTable } from "../../../src/cli/introspect/types.ts";

import {
  adoptableBlocks,
  describeProposal,
  type ExistingTable,
  existingTables,
  hasDefaultTable,
  proposeAdoption,
  qualifiedName,
} from "../../../src/cli/sql/adopt.ts";
import { SQL_MODULES } from "../../../src/sql/index.ts";

const table = (
  name: string,
  columns: Record<string, string>,
): ExistingTable => {
  const [schema, bare] = qualifiedName(name).split(".");
  return {
    schema: schema!,
    name: bare!,
    columns: Object.entries(columns).map(([column, udt]) => ({
      name: column,
      udt,
    })),
  };
};

/** Every table of `block` under its default name, with its default columns. */
const defaults = (block: string): ExistingTable[] =>
  Object.values(SQL_MODULES[block]?.names?.tables ?? {}).map((spec) =>
    table(
      spec.name,
      Object.fromEntries(
        Object.values(spec.columns).map((column) => [column, "text"]),
      ),
    ),
  );

const TEAMS = table("teams", {
  id: "uuid",
  organization_id: "uuid",
  name: "text",
  slug: "text",
  description: "text",
  status: "text",
  created_by: "uuid",
  created_at: "timestamptz",
  updated_at: "timestamptz",
});

const MEMBERS = table("team_members", {
  team_id: "uuid",
  user_id: "uuid",
  organization_id: "uuid",
  created_at: "timestamptz",
});

describe("proposeAdoption", () => {
  it("maps a block onto tables under its default names, guessing renamed columns", () => {
    const proposal = proposeAdoption("teams", [TEAMS, MEMBERS]);
    expect(proposal.errors).toEqual([]);
    expect(proposal.entry).toEqual({
      mode: "adopt",
      tables: { teams: "public.teams", members: "public.team_members" },
      columns: {
        teams: { tenant: "organization_id" },
        members: { tenant: "organization_id" },
      },
    });
    expect(proposal.tables[0]?.columns).toContainEqual({
      logical: "tenant",
      column: "organization_id",
      by: "alias",
    });
  });

  it("assigns the tables in --from to the logical tables they match best", () => {
    const squads = { ...TEAMS, schema: "app", name: "squads" };
    const proposal = proposeAdoption("teams", [squads, MEMBERS], {
      from: ["app.squads"],
    });
    expect(proposal.entry.tables).toEqual({
      teams: "app.squads",
      members: "public.team_members",
    });
  });

  it("maps optional columns the table lacks to null, and reports required ones", () => {
    const organizations = table("organizations", {
      id: "uuid",
      name: "text",
      created_at: "timestamptz",
      updated_at: "timestamptz",
    });
    const proposal = proposeAdoption("organizations", [organizations]);
    expect(proposal.errors).toEqual([]);
    expect(proposal.entry.columns?.["organizations"]).toMatchObject({
      createdBy: null,
      deletedAt: null,
    });
    const missing = proposeAdoption("teams", [
      table("teams", { id: "uuid", organization_id: "uuid" }),
      MEMBERS,
    ]);
    expect(missing.errors.join("\n")).toContain(
      "public.teams has no column for teams.name (name by default)",
    );
  });

  it("takes the id type from the tenant column", () => {
    const proposal = proposeAdoption("teams", [
      {
        ...TEAMS,
        columns: TEAMS.columns.map((c) =>
          c.name === "organization_id" ? { ...c, udt: "int8" } : c,
        ),
      },
      {
        ...MEMBERS,
        columns: MEMBERS.columns.map((c) =>
          c.name === "organization_id" ? { ...c, udt: "int8" } : c,
        ),
      },
    ]);
    expect(proposal.entry.idType).toBe("bigint");
    const set = proposeAdoption("teams", [TEAMS, MEMBERS], {
      blocks: { teams: { idType: "uuid", options: {} } },
    });
    expect(set.entry.idType).toBe("uuid");
  });

  it("reports tables it can't find or match", () => {
    expect(
      proposeAdoption("teams", [MEMBERS], { from: ["public.nope"] }).errors,
    ).toEqual([
      "public.nope is not a table in the database.",
      "blocks.teams needs a table for teams (teams by default) and none was found. Pass it with --from.",
    ]);
    const unrelated = table("invoices", { total: "numeric" });
    expect(
      proposeAdoption("teams", [unrelated, TEAMS, MEMBERS], {
        from: ["invoices"],
      }).errors,
    ).toEqual([
      "public.invoices matches none of the teams tables (teams, members).",
    ]);
  });

  it("refuses blocks without an adopt mode", () => {
    expect(proposeAdoption("comments", []).errors[0]).toContain(
      "comments has no adopt mode. Blocks you can adopt: ",
    );
    expect(proposeAdoption("nope", []).errors).toEqual([
      "nope is not a block. See `better-supabase blocks list`.",
    ]);
    expect(adoptableBlocks()).toContain("teams");
  });

  it("reports what the module refuses in the merged entry", () => {
    const proposal = proposeAdoption("teams", [TEAMS, MEMBERS], {
      blocks: { teams: { options: { nope: true } } },
    });
    expect(proposal.errors).toEqual([
      expect.stringContaining('blocks.teams.options: unknown option "nope"'),
    ]);
  });

  it("warns about migration-only options the entry keeps", () => {
    const proposal = proposeAdoption("outbox", defaults("outbox"), {
      blocks: { outbox: { options: { defaultSource: "crm" } } },
    });
    expect(proposal.errors).toEqual([]);
    expect(proposal.warnings).toEqual([
      'blocks.outbox.options.defaultSource is "crm". It fills a source for events emitted without one.',
    ]);
  });
});

describe("hasDefaultTable", () => {
  it("finds a block's tables by their default names in the given schemas", () => {
    expect(hasDefaultTable("teams", [MEMBERS])).toBe(true);
    expect(hasDefaultTable("teams", [MEMBERS], ["app"])).toBe(false);
    expect(hasDefaultTable("nope", [MEMBERS])).toBe(false);
  });
});

describe("existingTables", () => {
  it("keeps tables and leaves out views", () => {
    const base = { schema: "public", columns: [] };
    // SAFETY: only the fields existingTables reads are set.
    const tables = [
      { ...base, name: "a", kind: "table" },
      { ...base, name: "b", kind: "view" },
    ] as unknown as CatalogTable[];
    expect(existingTables(tables).map((t) => t.name)).toEqual(["a"]);
  });
});

describe("describeProposal", () => {
  it("lists each table and column, then the report", () => {
    const lines = describeProposal(
      proposeAdoption("teams", [
        table("teams", { id: "uuid", organization_id: "uuid" }),
        MEMBERS,
      ]),
    );
    expect(lines).toContain("  teams: public.teams");
    expect(lines).toContain("    tenant       organization_id (guessed)");
    expect(lines).toContain("    name         null (not in the table)");
    expect(lines.some((line) => line.startsWith("  error  "))).toBe(true);
  });
});
