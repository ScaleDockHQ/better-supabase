import { describe, expect, it } from "vitest";

import { createOrganizations } from "../../../src/blocks/organizations/organizations.ts";

const rows = [
  { user_id: "u1", role: "member" },
  { user_id: "u2", role: "owner" },
];

const transport = { call: () => Promise.resolve(rows) };

describe("organizations helpers", () => {
  it("owner finds the member with the owner role", async () => {
    const organizations = createOrganizations({ transport });

    expect(await organizations.owner("o").orThrow()).toMatchObject({
      userId: "u2",
    });
  });

  it("owner takes the role name from options and is undefined without a match", async () => {
    const organizations = createOrganizations({
      transport,
      ownerRole: "founder",
    });

    expect(await organizations.owner("o").orThrow()).toBeUndefined();
  });

  it("memberRoles maps user ids to their roles", async () => {
    const organizations = createOrganizations({ transport });

    expect(await organizations.memberRoles("o").orThrow()).toEqual({
      u1: ["member"],
      u2: ["owner"],
    });
  });
});
