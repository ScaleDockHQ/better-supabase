import { describe, expect, it, vi } from "vitest";

import type { BlockTransport } from "../../../src/core/block-transport.ts";

import { createWorkflowEditor } from "../../../src/blocks/workflow-editor/workflow-editor.ts";

const AT = "2026-01-01T00:00:00Z";

const DEFINITION = {
  id: "d1",
  tenant: "t1",
  slug: "onboard",
  name: "Onboard",
  description: null,
  createdBy: "u1",
  createdAt: AT,
  updatedAt: AT,
  published: 2,
  draft: true,
};

function fake(replies: Record<string, unknown>) {
  const call = vi.fn(
    async (_schema: string, fn: string, _args: Record<string, unknown>) => {
      if (!(fn in replies)) {
        throw new Error(`unexpected ${fn}`);
      }

      return replies[fn];
    },
  );

  const transport: BlockTransport = { call };

  return { transport, call };
}

describe("workflow definition lists", () => {
  it("pages definitions with search, a state filter and a sort", async () => {
    const { transport, call } = fake({
      page_workflow_definitions: {
        items: [DEFINITION],
        hasMore: true,
        nextCursor: ["Onboard", "d1"],
      },
    });

    const page = await createWorkflowEditor({ transport })
      .definitions.page({
        organizationId: "t1",
        q: "onb",
        filters: { state: ["published", "draft"] },
        sort: { by: "updatedAt", direction: "desc" },
        limit: 25,
      })
      .orThrow();

    expect(page).toMatchObject({
      hasMore: true,
      nextCursor: ["Onboard", "d1"],
      items: [{ id: "d1", name: "Onboard", published: 2 }],
    });

    expect(call.mock.calls[0]?.[2]).toMatchObject({
      tenant: "t1",
      filters: {
        search: "onb",
        state: ["published", "draft"],
        sort: "updatedAt",
        direction: "desc",
        limit: 25,
        paged: true,
      },
    });
  });

  it("counts, facets and reads one definition or not_found", async () => {
    const { transport } = fake({
      page_workflow_definitions: { value: 3, exact: true },
      workflow_definition_get: null,
    });

    const builder = createWorkflowEditor({ transport });

    expect(
      await builder.definitions.count({ organizationId: "t1" }).orThrow(),
    ).toEqual({ value: 3, exact: true });

    const missing = await builder.definitions.getDefinition("nope");

    expect(!missing.ok && missing.error.kind).toBe("not_found");
  });

  it("refuses a sort or filter the entity does not declare", async () => {
    const { transport } = fake({});

    const refused = await createWorkflowEditor({ transport }).definitions.page({
      organizationId: "t1",
      sort: { by: "slug", direction: "asc" },
    });

    expect(!refused.ok && refused.error.kind).toBe("invalid_input");
  });
});
