import { describe, expect, it } from "vitest";

import { createTeams } from "../../../src/blocks/teams/teams.ts";

function setup(members: string[]) {
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
});
