import { describe, expect, it } from "vitest";

import { tenantNames } from "../../src/core/tenant-naming.ts";

describe("tenantNames", () => {
  it("keeps every identifier under the default name", () => {
    const names = tenantNames();
    expect(names).toMatchObject({
      singular: "organization",
      plural: "organizations",
      renamed: false,
    });
    expect(names.rename("create_organization")).toBe("create_organization");
  });

  it("renames the singular and the plural", () => {
    const names = tenantNames("workspace");
    expect(names.renamed).toBe(true);
    expect(names.rename("create_organization")).toBe("create_workspace");
    expect(names.rename("organizations")).toBe("workspaces");
    expect(names.rename("organization_id")).toBe("workspace_id");
    expect(names.rename("member_organization_ids")).toBe(
      "member_workspace_ids",
    );
    expect(names.rename("tags")).toBe("tags");
  });

  it("forms English plurals", () => {
    expect(tenantNames("company").plural).toBe("companies");
    expect(tenantNames("business").plural).toBe("businesses");
    expect(tenantNames("team").rename("organizations_slug_idx")).toBe(
      "teams_slug_idx",
    );
  });

  it("rejects a name that is not a lowercase identifier", () => {
    expect(() => tenantNames("Work space")).toThrow(
      /sql.naming.tenant: "Work space" is not a lowercase identifier/,
    );
  });
});
