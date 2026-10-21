import { describe, expect, it } from "vitest";

import {
  composeNames,
  entityNames,
  entityNoun,
  pluralOf,
  tenantNames,
} from "../../src/core/entity-naming.ts";

const task = { from: entityNoun("work_item"), to: entityNoun("task") };

describe("entityNames", () => {
  it("leaves identifiers alone without renames", () => {
    const names = entityNames();
    expect(names.renamed).toBe(false);
    expect(names.rename("create_work_item")).toBe("create_work_item");
  });

  it("renames every case form, singular and plural", () => {
    const names = entityNames([task]);
    expect(names.renamed).toBe(true);
    expect(names.rename("list_work_items")).toBe("list_tasks");
    expect(names.rename("work_item_id")).toBe("task_id");
    expect(names.rename("work_items.read")).toBe("tasks.read");
    expect(names.rename("work_item.created")).toBe("task.created");
    expect(names.rename("work-items/")).toBe("tasks/");
    expect(names.rename("workItemId")).toBe("taskId");
    expect(names.rename("WorkItemInput")).toBe("TaskInput");
    expect(names.rename("listWorkItems")).toBe("listTasks");
  });

  it("matches whole segments only", () => {
    const names = entityNames([
      { from: entityNoun("deal"), to: entityNoun("opportunity") },
    ]);

    expect(names.rename("deal_id")).toBe("opportunity_id");
    expect(names.rename("ideal")).toBe("ideal");
    expect(names.rename("dealer")).toBe("dealer");
    expect(names.rename("Dealer")).toBe("Dealer");
    expect(names.rename("listDeals")).toBe("listOpportunities");
  });

  it("handles irregular plurals and overlapping nouns, longest first", () => {
    const names = entityNames([
      { from: entityNoun("person", "people"), to: entityNoun("contact") },
      { from: entityNoun("product"), to: entityNoun("item") },
      { from: entityNoun("product_variant"), to: entityNoun("sku") },
    ]);

    expect(names.rename("list_people")).toBe("list_contacts");
    expect(names.rename("product_variants")).toBe("skus");
    expect(names.rename("product_variant_values")).toBe("sku_values");
    expect(names.rename("products")).toBe("items");
  });

  it("reverses a rename", () => {
    const names = entityNames([task]);
    expect(names.reverse("task_id")).toBe("work_item_id");
    expect(names.reverse("taskId")).toBe("workItemId");
    expect(names.reverse("tasks")).toBe("work_items");
  });

  it("composes rename sets in one pass", () => {
    const names = composeNames(tenantNames("workspace"), entityNames([task]));
    expect(names.rename("work_item_organization_idx")).toBe(
      "task_workspace_idx",
    );
  });
});

describe("tenantNames", () => {
  it("renames the tenant inside any identifier, lowercase forms only", () => {
    const names = tenantNames("workspace");
    expect(names.rename("create_organization")).toBe("create_workspace");
    expect(names.rename("organizations")).toBe("workspaces");
    expect(names.rename("member_organization_ids")).toBe(
      "member_workspace_ids",
    );
    expect(names.rename("organizationId")).toBe("workspaceId");
    expect(names.rename("Organization")).toBe("Organization");
    expect(names.rename("tags")).toBe("tags");
  });

  it("forms English plurals", () => {
    expect(pluralOf("company")).toBe("companies");
    expect(pluralOf("business")).toBe("businesses");
    expect(tenantNames("team").rename("organizations_slug_idx")).toBe(
      "teams_slug_idx",
    );
  });

  it("rejects a name that is not a lowercase identifier", () => {
    expect(() => tenantNames("Work space")).toThrow(
      /blocks.tenant.entities.organization: "Work space" is not a lowercase identifier/,
    );
  });
});
