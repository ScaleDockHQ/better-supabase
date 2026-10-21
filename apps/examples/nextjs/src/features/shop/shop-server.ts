import "server-only";
import type { RpcClient } from "better-supabase/blocks";
import type { Orders } from "better-supabase/blocks/orders";

import { generatedOptions } from "better-supabase/blocks";
import { createOrders, rpcTransport } from "better-supabase/blocks/orders";

import { blockConfig } from "@/lib/supabase/blocks.generated";
import { bs } from "@/lib/supabase/server";

const API_SCHEMA = blockConfig.orders.api;

/**
 * The orders block acting as the caller. Placing the order and recording a
 * payment are service only (`place_order`, `record_payment`), so checkout and
 * the manual "mark as paid" go through the service role after the caller's own
 * calls have read the cart or order.
 */
export function shopOrders(supabase: RpcClient): Orders {
  return createOrders({
    ...generatedOptions(blockConfig.orders),
    transport: rpcTransport(supabase, { schema: API_SCHEMA }),
    service: rpcTransport(bs.admin().$client, { schema: API_SCHEMA }),
  });
}
