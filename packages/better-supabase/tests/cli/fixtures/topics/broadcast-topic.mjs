import { defineTopic } from "../../../../src/realtime/index.ts";

export const orders = defineTopic("org:{organizationId}:orders", {
  broadcast: [
    { table: "public.orders", event: "changed", payload: "row" },
    {
      table: "public.order_lines",
      events: ["insert", "update"],
      when: { changed: ["status"] },
    },
  ],
});

export const plain = defineTopic("org:{organizationId}:plain");
