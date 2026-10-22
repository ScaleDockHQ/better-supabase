"use client";

import { KITCHEN_EVENT } from "better-supabase/blocks/orders";
import { useBroadcast } from "better-supabase/react";
import { defineTopic } from "better-supabase/realtime";

import { useRouter } from "@/i18n/navigation";

const kitchen = defineTopic("kitchen:{organizationId}");

/**
 * Refreshes the page when a line changes state anywhere in the organization's
 * kitchen. The orders block broadcasts on the private `kitchen:<org>` topic,
 * which members with `orders.read` or `orders.prepare` can receive.
 */
export function KitchenLive({ organizationId }: { organizationId: string }) {
  const router = useRouter();

  useBroadcast(
    kitchen,
    { organizationId },
    {
      [KITCHEN_EVENT]: () => {
        router.refresh();
      },
    },
  );

  return null;
}
