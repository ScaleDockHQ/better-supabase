import { createTax } from "better-supabase/blocks/tax";
import { money } from "better-supabase/commerce";

type Transport = Parameters<typeof createTax>[0]["transport"];

/** Computes the tax of a 100.00 EUR line with the rate valid on its date. */
export async function taxOfOneLine(transport: Transport, codeId: string) {
  const tax = createTax({ transport, tenant: "org-1" });

  return tax
    .computeDocumentTax({
      currency: "EUR",
      onDate: "2026-06-30",
      lines: [
        { quantity: 1, unitAmount: money(10_000n, "EUR"), taxCodeId: codeId },
      ],
    })
    .orThrow();
}
