import { createWarehouse } from "better-supabase/blocks/warehouse";

type Transport = Parameters<typeof createWarehouse>[0]["transport"];

/** Slots a bin, adds a putaway rule and asks where 8 units should go. */
export async function suggestWhere(
  transport: Transport,
  ids: { binId: string; variantId: string; locationId: string },
) {
  const warehouse = createWarehouse({ transport, tenant: "org-1" });

  await warehouse.saveBinSlot({ binId: ids.binId, walkRank: 1, capacity: 40 });
  await warehouse.savePutawayRule({
    binId: ids.binId,
    variantId: ids.variantId,
    priority: 1,
  });

  return {
    putaway: await warehouse.suggestPutaway({
      locationId: ids.locationId,
      variantId: ids.variantId,
      quantity: 8,
    }),
    slotting: await warehouse.suggestSlotting({
      locationId: ids.locationId,
      days: 30,
    }),
  };
}
