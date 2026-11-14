import { describe, expect, it } from "vitest";

import { createTeams } from "../../../src/blocks/teams/teams.ts";

function setup(members: string[], employees?: string[][]) {
  const pending = [...(employees ?? [])];

  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    teams: createTeams({
      transport: {
        call(_schema: string, fn: string, args: Record<string, unknown>) {
          calls.push([fn, args]);

          return Promise.resolve(
            fn === "list_teams"
              ? [
                  {
                    id: "t1",
                    name: "A",
                    slug: "a",
                    status: "active",
                    member_ids: members,
                    ...(employees === undefined
                      ? {}
                      : {
                          member_employee_ids:
                            pending.length > 1 ? pending.shift() : pending[0],
                        }),
                  },
                ]
              : true,
          );
        },
      },
    }),
  };
}

describe("teams.setMembers and setArchived", () => {
  it("adds the missing members and removes the others", async () => {
    const { teams, calls } = setup(["u1", "u2"]);

    const changed = await teams
      .setMembers({ organizationId: "o", teamId: "t1", userIds: ["u2", "u3"] })
      .orThrow();

    expect(changed).toEqual({ added: ["u3"], removed: ["u1"] });
    expect(calls.map(([fn]) => fn)).toEqual([
      "list_teams",
      "add_team_member",
      "remove_team_member",
    ]);
  });

  it("fails with not_found for a team outside the organization", async () => {
    const { teams } = setup([]);

    const result = await teams.setMembers({
      organizationId: "o",
      teamId: "other",
      userIds: [],
    });

    expect(!result.ok && result.error.kind).toBe("not_found");
  });

  it("setArchived archives or restores", async () => {
    const { teams, calls } = setup([]);

    await teams.setArchived({ teamId: "t1", archived: true });
    await teams.setArchived({ teamId: "t1", archived: false });

    expect(calls.map(([fn]) => fn)).toEqual(["archive_team", "restore_team"]);
  });

  it("adds and removes employees, reading the list again after the users", async () => {
    const { teams, calls } = setup(["u1"], [["e1", "e2"], ["e1"]]);

    const changed = await teams
      .setMembers({
        organizationId: "o",
        teamId: "t1",
        userIds: [],
        employeeIds: ["e2", "e3"],
      })
      .orThrow();

    expect(changed).toEqual({
      added: [],
      removed: ["u1"],
      addedEmployees: ["e2", "e3"],
      removedEmployees: ["e1"],
    });
    expect(calls).toEqual([
      ["list_teams", { tenant: "o" }],
      ["remove_team_member", { team: "t1", member: "u1" }],
      ["list_teams", { tenant: "o" }],
      ["add_team_member", { team: "t1", employee: "e2" }],
      ["add_team_member", { team: "t1", employee: "e3" }],
      ["remove_team_member", { team: "t1", employee: "e1" }],
    ]);
  });

  it("leaves the users alone when only employeeIds is given", async () => {
    const { teams, calls } = setup(["u1"], [["e1"]]);

    await teams
      .setMembers({ organizationId: "o", teamId: "t1", employeeIds: ["e1"] })
      .orThrow();

    expect(calls.map(([fn]) => fn)).toEqual(["list_teams"]);
  });

  it("reads memberEmployeeIds, empty without the employees block", async () => {
    const without = await setup(["u1"]).teams.list("o").orThrow();

    const withEmployees = await setup(["u1"], [["e1"]])
      .teams.list("o")
      .orThrow();

    expect(without[0]?.memberEmployeeIds).toEqual([]);
    expect(withEmployees[0]?.memberEmployeeIds).toEqual(["e1"]);
  });

  it("purges a team through purge_team, a name that says it is final", async () => {
    const { teams, calls } = setup([]);

    expect(await teams.purge("t1").orThrow()).toBe(true);
    expect(calls).toEqual([["purge_team", { team: "t1" }]]);
  });
});
