import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { createInventory } from "../../src/blocks/inventory/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { testBlockList } from "../../src/testing/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

describe.skipIf(!live)(
  "the inventory lookup lists follow the list contract",
  () => {
    const pool = new Pool({ connectionString: dbUrl, max: 2 });

    afterAll(() => pool.end());

    it("pages locations, bins and variants", async () => {
      const s = await BlockSession.open(pool);

      try {
        await s.install(["organizations", "catalog", "inventory"]);
        const owner = await s.user("lookups-owner");
        const org = await s.organization(owner);
        await s.asRole(owner);

        const inventory = createInventory({ transport: sqlTransport(s.sql) });

        const place = async (code: string, kind: string): Promise<string> =>
          (
            await s.value<{ id: string }>(
              "better_supabase.upsert_location($1, null, $2, $3, $4)",
              [org, code, `${code} depot`, kind],
            )
          ).id;

        const warehouseA = await place("ALPHA-1", "warehouse");
        await place("ALPHA-2", "store");
        await place("BETA-1", "warehouse");
        await place("GAMMA-1", "store");
        await place("GAMMA-2", "store");

        await testBlockList({
          name: "inventory.locations",
          target: {
            page: (options) =>
              inventory.locationPage({ ...options, organizationId: org }),
            count: (options) =>
              inventory.locationCount({ ...options, organizationId: org }),
            facets: (options) =>
              inventory.locationFacets({ ...options, organizationId: org }),
          },
          rows: 5,
          sorts: ["code", "name"],
          facets: { kind: { warehouse: 2, store: 3 } },
          arrayFilter: { column: "kind", values: ["warehouse", "store"] },
          search: "ALPHA",
        });

        const inactive = await inventory
          .locationPage({ organizationId: org, filters: { active: ["false"] } })
          .orThrow();

        expect(inactive.items).toEqual([]);

        for (const [index, code] of ["A-1", "A-2", "B-1", "B-2"].entries()) {
          await s.value(
            "better_supabase.upsert_bin($1, null, $2, $3, false, true)",
            [warehouseA, code, `Bin ${String(index)}`],
          );
        }

        await testBlockList({
          name: "inventory.bins",
          target: {
            page: (options) =>
              inventory.binPage({ ...options, organizationId: org }),
            count: (options) =>
              inventory.binCount({ ...options, organizationId: org }),
            facets: (options) =>
              inventory.binFacets({ ...options, organizationId: org }),
          },
          rows: 4,
          sorts: ["code"],
          facets: { locationId: { [warehouseA]: 4 } },
          search: "A-",
        });

        for (const sku of ["BEAN-1", "BEAN-2", "CORN-1", "CORN-2"]) {
          const product = await s.value<{ id: string }>(
            "better_supabase.upsert_product($1, null, $2, null, null, 'physical')",
            [org, sku],
          );

          await s.value(
            "better_supabase.upsert_variant($1, null, $2, '{}'::uuid[], null, null, null, true, false)",
            [product.id, sku],
          );
        }

        await testBlockList({
          name: "inventory.variants",
          target: {
            page: (options) =>
              inventory.variantPage({ ...options, organizationId: org }),
            count: (options) =>
              inventory.variantCount({ ...options, organizationId: org }),
          },
          rows: 4,
          sorts: ["sku"],
          search: "BEAN",
        });
      } finally {
        await s.close();
      }
    });
  },
);
