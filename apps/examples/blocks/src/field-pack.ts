import { defineFieldPack } from "better-supabase/blocks/custom-fields";

/** Fields a consultancy adds to its deals, installed once per organization. */
export const consultancyPack = defineFieldPack({
  apiVersion: 1,
  key: "consultancy",
  version: 1,
  subjects: {
    deal: [
      { key: "billing_model", label: "Billing model", type: "text" },
      { key: "purchase_order", label: "Purchase order", type: "text" },
    ],
  },
});
