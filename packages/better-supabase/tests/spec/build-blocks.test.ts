import { describe, expect, it } from "vitest";

import type { BlockContext } from "../../src/blocks/index.ts";

import { defineBlock, defineBlocks } from "../../src/blocks/index.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { ok } from "../../src/core/result.ts";
import { defineApi } from "../../src/spec/index.ts";
import { schema } from "../fixtures/generated-camel.ts";

const info = { title: "CRM", version: "1.0.0" };

const invoicing = defineBlock({
  name: "invoicing",
  category: "work",
  create: (_context: BlockContext) => ({
    create: async (input: { readonly total: number }) => ok(input),
    list: async () => ok([]),
    issue: async (id: string) => ok({ id }),
    relayRoute: () => () => new Response(null),
    drafts: { list: async () => ok([]) },
  }),
});

const blocks = defineBlocks(
  {
    invoicing: { schema: "better_supabase", options: {} },
    "invoicing-eu": {
      block: "invoicing",
      schema: "better_supabase",
      options: {},
    },
  },
  { invoicing, "invoicing-eu": invoicing },
);

const betterSupabase = defineSupabase(schema).blocks(blocks);

const ids = (api: { model: { operations: readonly { id: string }[] } }) =>
  api.model.operations.map((operation) => operation.id);

describe("defineApi: block instances", () => {
  it("publishes every instance and table by default", () => {
    const api = defineApi(betterSupabase, { info });

    expect(ids(api)).toContain("listCustomers");
    expect(ids(api)).toContain("countTasks");
    expect(ids(api)).toEqual(
      expect.arrayContaining([
        "invoicing.create",
        "invoicing.list",
        "invoicing.issue",
        "invoicing.drafts.list",
        "invoicingEu.create",
      ]),
    );
    expect(ids(api)).not.toContain("invoicing.relayRoute");
    expect(
      api.model.operations.find((entry) => entry.id === "invoicingEu.create"),
    ).toMatchObject({ method: "post", path: "/invoicing-eu/create" });
  });

  it("publishes only the listed instances and verbs", () => {
    const api = defineApi(betterSupabase, {
      info,
      resources: false,
      blocks: {
        invoicing: { verbs: ["list"], path: "/billing", tag: "Billing" },
      },
    });

    expect(api.diagnostics).toEqual([]);
    expect(api.model.operations).toMatchObject([
      { id: "invoicing.list", path: "/billing/list", tags: ["Billing"] },
    ]);
    expect(
      ids(defineApi(betterSupabase, { info, blocks: false })),
    ).not.toContain("invoicing.list");
  });

  it("reports unknown instances and verbs", () => {
    const api = defineApi(betterSupabase, {
      info,
      resources: false,
      blocks: { nope: true, invoicing: { verbs: ["missing"] } },
    });

    expect(api.diagnostics.map((entry) => entry.code)).toEqual([
      "block-unknown",
      "block-verb-unknown",
    ]);
  });

  it("requires a permission on block writes but not on reads", () => {
    const api = defineApi(betterSupabase, {
      info,
      resources: false,
      requirePermissions: true,
      blocks: {
        invoicing: {
          verbs: ["list", "create", "issue"],
          permissions: { issue: "invoices.issue" },
        },
      },
    });

    expect(
      api.diagnostics
        .filter((entry) => entry.code === "permission-missing")
        .map((entry) => entry.pointer),
    ).toEqual(["/operations/invoicing.create"]);
  });
});
