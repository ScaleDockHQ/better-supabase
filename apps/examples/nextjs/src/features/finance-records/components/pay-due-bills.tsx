import { getExtracted } from "next-intl/server";

import { payDueBills } from "@/features/composites/composites-actions";
import { ActionDialog } from "@/features/sales/components/action-dialog";
import { bsb } from "@/lib/supabase/server";

/**
 * Batches the supplier bills due by a day, posts the batch to the books and
 * exports the SEPA file in one action: `procurement.payDueBills`. Render it
 * inside `<Suspense>` behind the permission that manages banking.
 */
// skeleton: its parent page or section renders it inside a Suspense with a fallback of the same shape.
export async function PayDueBillsButton() {
  const [t, { db }] = await Promise.all([
    getExtracted("finance"),
    bsb.context(),
  ]);

  const accounts = await db.banking.accountPage({ limit: 50 });

  if (!accounts.ok || accounts.data.items.length === 0) {
    return null;
  }

  return (
    <ActionDialog
      action={payDueBills}
      title={t("Pay the bills that are due")}
      description={t(
        "One batch pays every purchase bill due by the day, posts it to the books and exports the bank file.",
      )}
      trigger={t("Pay due bills")}
      submitLabel={t("Pay bills")}
      successMessage={t("Bills paid")}
      variant="outline"
      fields={[
        {
          name: "accountId",
          label: t("Pay from"),
          kind: "select",
          options: accounts.data.items.map((account) => ({
            value: account.id,
            label: account.name,
          })),
        },
        { name: "dueBy", label: t("Due by"), kind: "date", required: true },
        {
          name: "creditorName",
          label: t("Supplier name on the bank file"),
          kind: "text",
          required: true,
        },
        {
          name: "creditorIban",
          label: t("Supplier IBAN"),
          kind: "text",
          required: true,
          placeholder: "NL91ABNA0417164300",
        },
      ]}
    />
  );
}
