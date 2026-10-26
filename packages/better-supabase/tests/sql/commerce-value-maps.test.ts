import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../src/config/blocks.ts";

import { renderBlocks } from "../../src/sql/render.ts";
import { ownTablesOf } from "../fixtures/own-tables.ts";

function sqlOf(blocks: readonly string[], modules: AnyBlocksConfig): string {
  return renderBlocks(blocks, {
    modules,
    ownTables: ownTablesOf(modules, blocks),
  })
    .filter((file) => blocks.includes(file.module))
    .map((file) => file.contents)
    .join("\n");
}

describe("value maps in the commerce modules", () => {
  it("maps shipment and tracking statuses", () => {
    const sql = sqlOf(["shipments"], {
      shipments: {
        values: {
          shipments: { status: { cancelled: "voided", draft: "new" } },
          trackingEvents: { status: { label_created: "labelled" } },
        },
      },
    });

    expect(sql).toContain(`= 'voided',`);
    expect(sql).toContain(`not in ('new', 'label_created')`);
    expect(sql).toContain(`'labelled', now()`);
    expect(sql).toContain(`when 'voided' then 'cancelled'`);
  });

  it("maps reservation, transfer and purchase order statuses", () => {
    const sql = sqlOf(["inventory"], {
      inventory: {
        values: {
          reservations: { status: { active: "held", expired: "lapsed" } },
          transfers: { status: { in_transit: "shipped" } },
          purchaseOrders: { status: { ordered: "sent" } },
        },
      },
    });

    expect(sql).toContain(`"status" = 'held'`);
    expect(sql).toContain(`= 'lapsed'`);
    expect(sql).toContain(`= 'shipped',`);
    expect(sql).toContain(`= 'sent',`);
    expect(sql).toContain(`when 'held' then 'active'`);
  });

  it("maps cart, order, payment and fulfillment statuses", () => {
    const sql = sqlOf(["orders"], {
      orders: {
        values: {
          carts: { status: { open: "active", abandoned: "dropped" } },
          orders: { status: { pending_payment: "awaiting_payment" } },
          payments: { status: { canceled: ["canceled", "voided"] } },
          fulfillments: { status: { shipped: "sent" } },
        },
      },
    });

    expect(sql).toContain(`"status" = 'active' do update`);
    expect(sql).toContain(`= 'dropped',`);
    expect(sql).toContain(`= 'awaiting_payment' and`);
    expect(sql).toContain(`in ('succeeded', 'failed', 'canceled', 'voided')`);
    expect(sql).toContain(`= 'sent',`);
  });
});
