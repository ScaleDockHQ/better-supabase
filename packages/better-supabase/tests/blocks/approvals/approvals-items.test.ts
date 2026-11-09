import { describe, expect, it } from "vitest";

import { createApprovals } from "../../../src/blocks/approvals/index.ts";
import { renderBlocks } from "../../../src/sql/render.ts";

type Handler = (args: Record<string, unknown>) => unknown;

function isHandler(value: unknown): value is Handler {
  return typeof value === "function";
}

function transport(results: Record<string, unknown>) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    call(_schema: string, fn: string, args: Readonly<Record<string, unknown>>) {
      calls.push([fn, { ...args }]);
      const result = results[fn];

      if (result === undefined) {
        return Promise.reject(new Error(`unexpected ${fn}`));
      }

      return Promise.resolve(isHandler(result) ? result({ ...args }) : result);
    },
  };
}

const ITEM = {
  id: "i1",
  key: "invoice",
  label: "Invoice",
  payload: { total: 5 },
  permission: "invoices.approve",
  dependsOn: [],
  status: "pending",
  createdAt: "2026-10-01T00:00:00Z",
};

const REQUEST = {
  id: "r1",
  organizationId: "o",
  subjectType: "chat",
  subjectId: "c1",
  action: "run",
  status: "pending",
  step: 0,
  steps: [],
  createdAt: "2026-10-01T00:00:00Z",
  items: [ITEM],
};

const SUBJECT = { type: "chat", id: "c1" };

describe("approval items", () => {
  it("passes an item's fields through and reads them back on get", async () => {
    const fake = transport({
      request_approval_items: REQUEST,
      get_approval: {
        ...REQUEST,
        canDecide: true,
        decisions: [],
        items: [{ ...ITEM, fields: { cost_center: "ops" } }],
      },
    });

    const approvals = createApprovals({ transport: fake, tenant: "o" });

    await approvals.request({
      subject: SUBJECT,
      input: {
        action: "run",
        items: [{ key: "invoice", fields: { cost_center: "ops" } }],
      },
    });

    const got = await approvals.get("r1");

    expect(fake.calls[0]?.[1]["items"]).toEqual([
      expect.objectContaining({ fields: { cost_center: "ops" } }),
    ]);
    expect(got.ok && got.data.items[0]?.fields).toEqual({ cost_center: "ops" });
  });

  it("files a request with items through request_approval_items", async () => {
    const fake = transport({ request_approval_items: REQUEST });
    const approvals = createApprovals({ transport: fake, tenant: "o" });

    const result = await approvals.request({
      subject: SUBJECT,
      input: {
        action: "run",
        items: [
          { key: "invoice", label: "Invoice", permission: "invoices.approve" },
          { key: "send", dependsOn: ["invoice"] },
        ],
      },
    });

    expect(result.ok).toBe(true);
    expect(fake.calls[0]?.[0]).toBe("request_approval_items");
    expect(fake.calls[0]?.[1]["items"]).toEqual([
      {
        key: "invoice",
        label: "Invoice",
        payload: {},
        permission: "invoices.approve",
        dependsOn: [],
      },
      {
        key: "send",
        label: null,
        payload: {},
        permission: null,
        dependsOn: ["invoice"],
      },
    ]);
  });

  it("decides items and reads the items back", async () => {
    const fake = transport({
      decide_approval_items: {
        ...REQUEST,
        status: "approved",
        items: [
          {
            ...ITEM,
            status: "approved",
            decidedBy: "u2",
            decidedAt: "2026-10-02T00:00:00Z",
            createdType: "invoice",
            createdId: "inv1",
          },
        ],
      },
    });

    const result = await createApprovals({
      transport: fake,
      tenant: "o",
    }).decideItems({
      id: "r1",
      decisions: [
        { key: "invoice", decision: "approve" },
        { key: "send", decision: "reject" },
      ],
      decidedBy: "u2",
    });

    expect(fake.calls[0]?.[1]).toEqual({
      request_id: "r1",
      decisions: [
        { key: "invoice", decision: "approved" },
        { key: "send", decision: "rejected" },
      ],
      decided_by: "u2",
    });
    expect(result.ok && result.data.items[0]).toMatchObject({
      status: "approved",
      decidedBy: "u2",
      created: { type: "invoice", id: "inv1" },
    });
  });

  it("records what an item created and settles a request", async () => {
    const fake = transport({
      record_approval_created: {
        ...ITEM,
        status: "approved",
        createdType: "invoice",
        createdId: "inv1",
      },
      settle_approval: { ...REQUEST, status: "rejected", items: [] },
    });

    const approvals = createApprovals({ transport: fake, tenant: "o" });

    const recorded = await approvals.recordCreated({
      id: "r1",
      key: "invoice",
      type: "invoice",
      recordId: "inv1",
    });

    const settled = await approvals.settle({
      id: "r1",
      outcome: "rejected",
      reason: "run failed",
    });

    expect(recorded.ok && recorded.data.created).toEqual({
      type: "invoice",
      id: "inv1",
    });
    expect(fake.calls[0]?.[1]).toEqual({
      request_id: "r1",
      item_key: "invoice",
      created_type: "invoice",
      created_id: "inv1",
    });
    expect(fake.calls[1]?.[1]).toEqual({
      request_id: "r1",
      outcome: "rejected",
      reason: "run failed",
    });
    expect(settled.ok && settled.data.status).toBe("rejected");
  });

  it("passes decidedBy through decideForSubject", async () => {
    const fake = transport({
      list_approvals: [REQUEST],
      decide_approval: REQUEST,
    });

    await createApprovals({ transport: fake, tenant: "o" }).decideForSubject({
      subject: SUBJECT,
      action: "run",
      decision: "approve",
      decidedBy: "u3",
    });

    expect(fake.calls[1]?.[1]).toMatchObject({ decided_by: "u3" });
  });

  it("reads items on get", async () => {
    const fake = transport({
      get_approval: { ...REQUEST, canDecide: true, decisions: [] },
    });

    const result = await createApprovals({ transport: fake, tenant: "o" }).get(
      "r1",
    );

    expect(result.ok && result.data.items).toHaveLength(1);
  });
});

describe("approval items SQL", () => {
  const files = renderBlocks(["approvals"], {});

  const sql = files
    .filter((file) => file.module === "approvals")
    .map((file) => file.contents)
    .join("\n");

  it("creates the table and the four functions", () => {
    expect(sql).toContain("approval_items");

    for (const name of [
      "request_approval_items",
      "decide_approval_items",
      "record_approval_created",
      "settle_approval",
    ]) {
      expect(sql).toContain(`"${name}"`);
    }
  });

  it("blocks approval behind a dependency and settles when none is pending", () => {
    expect(sql).toContain("APPROVAL_ITEM_BLOCKED");
    expect(sql).toContain("v_pending = 0");
    expect(sql).toContain("APPROVAL_ITEMS_REQUIRED");
  });

  it("limits settle_approval to the service role", () => {
    expect(sql).toMatch(
      /grant execute on function "better_supabase"\."settle_approval"\(uuid, text, text\) to service_role/,
    );
  });
});
