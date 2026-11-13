import { describe, expect, it } from "vitest";

import {
  createInvoices,
  invoicesBinding,
  invoicesBlock,
} from "../../../src/blocks/invoices/index.ts";

describe("invoicesBinding", () => {
  it("reads the subject's invoices in the block's organization", async () => {
    const calls: [string, Record<string, unknown>][] = [];

    const client = createInvoices({
      tenant: "org-1",
      transport: {
        call(_schema: string, fn: string, args: Record<string, unknown>) {
          calls.push([fn, args]);

          return Promise.resolve([]);
        },
      },
    });

    const loaded = await invoicesBinding.load(
      client,
      { type: "company", id: "c1" },
      undefined,
    );

    expect(loaded.ok && loaded.data).toEqual([]);
    expect(calls).toEqual([
      [
        "list_invoices_for_subject",
        {
          tenant: "org-1",
          subject_type: "company",
          subject_id: "c1",
          page_size: null,
        },
      ],
    ]);
    expect(invoicesBlock.record).toBe(invoicesBinding);
  });

  it("fails without an organization", async () => {
    const client = createInvoices({
      transport: { call: () => Promise.resolve([]) },
    });

    const loaded = await client.list({
      subject: { type: "company", id: "c1" },
    });

    expect(loaded.ok).toBe(false);
  });
});
