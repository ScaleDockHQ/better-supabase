import { describe, expect, it } from "vitest";

import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";
import type { CatalogColumn } from "../../../src/cli/introspect/types.ts";

import { requiredTeamMemberUser } from "../../../src/cli/doctor/team-members.ts";
import { fromCatalog } from "../../../src/cli/introspect/from-catalog.ts";
import { resolveConfig } from "../../../src/config/index.ts";

const column = (name: string, nullable: boolean): CatalogColumn => ({
  name,
  udt: "uuid",
  format: "uuid",
  typeSchema: "pg_catalog",
  isArray: false,
  isEnum: false,
  nullable,
  hasDefault: false,
  default: null,
  identity: null,
  generated: false,
  updatable: true,
  comment: null,
});

const members = { tables: { members: "public.team_members" } };

const context = (
  columns: readonly CatalogColumn[],
  teams: Record<string, unknown> = members,
): DoctorContext => ({
  config: resolveConfig({ blocks: { teams, employees: {} } }, "/project"),
  snapshot: fromCatalog({
    schemas: ["public"],
    tables: [
      {
        schema: "public",
        name: "team_members",
        kind: "table",
        comment: null,
        rls: true,
        forceRls: false,
        insertable: true,
        updatable: true,
        columns,
        primaryKey: ["team_id", "user_id"],
        foreignKeys: [],
        uniques: [],
        indexes: [],
        checks: [],
        triggers: [],
        policies: [],
        grants: [],
        columnGrants: [],
      },
    ],
    enums: [],
    functions: [],
    buckets: [],
  } as never),
  configToml: undefined,
  envFiles: [],
  gitignore: "",
  sources: [],
});

describe("team members with a required user (BS631)", () => {
  it("reports an app table with employees and a not-null user", () => {
    expect(
      requiredTeamMemberUser(
        context([
          column("team_id", false),
          column("user_id", false),
          column("employee_id", true),
        ]),
      ),
    ).toEqual([
      expect.objectContaining({ target: "public.team_members.user_id" }),
    ]);
  });

  it("passes a user-only table, a nullable user, a null mapping and the block's table", () => {
    const userOnly = [column("team_id", false), column("user_id", false)];

    const nullable = [
      column("team_id", false),
      column("user_id", true),
      column("employee_id", true),
    ];

    const required = [
      column("team_id", false),
      column("user_id", false),
      column("employee_id", true),
    ];

    expect(requiredTeamMemberUser(context(userOnly))).toEqual([]);
    expect(requiredTeamMemberUser(context(nullable))).toEqual([]);
    expect(
      requiredTeamMemberUser(
        context(required, {
          tables: { members: "public.team_members" },
          columns: { members: { employee: null } },
        }),
      ),
    ).toEqual([]);
    expect(requiredTeamMemberUser(context(required, {}))).toEqual([]);
  });

  it("passes custom modes, a missing employees block and a table the database lacks", () => {
    const required = [
      column("team_id", false),
      column("user_id", false),
      column("employee_id", true),
    ];

    const custom = context(required);

    expect(
      requiredTeamMemberUser({
        ...custom,
        config: {
          ...custom.config,
          blocks: {
            ...custom.config.blocks,
            teams: { ...custom.config.blocks["teams"], mode: "custom" },
          },
        },
      }),
    ).toEqual([]);
    expect(
      requiredTeamMemberUser({
        ...custom,
        config: resolveConfig({ blocks: { teams: members } }, "/project"),
      }),
    ).toEqual([]);
    expect(
      requiredTeamMemberUser(
        context(required, { tables: { members: "other_members" } }),
      ),
    ).toEqual([]);
    expect(
      requiredTeamMemberUser(
        context(required, {
          ...members,
          columns: { members: { user: "member_id", employee: "staff_id" } },
        }),
      ),
    ).toEqual([]);
  });
});
