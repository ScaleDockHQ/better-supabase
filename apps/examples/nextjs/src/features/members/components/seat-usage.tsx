import { getExtracted } from "next-intl/server";

import { KpiBand } from "@/components/record-list/kpi-band";

import { loadSeatsLeft } from "../seats/seats-queries";

/** The seat figures of the members page; render inside `<Suspense>`. */
// skeleton: its parent page or section renders it inside a Suspense with a fallback of the same shape.
export async function SeatUsage({ used }: { used: number }) {
  const [left, t] = await Promise.all([
    loadSeatsLeft(used),
    getExtracted("members"),
  ]);

  if (left === null) {
    return null;
  }

  return (
    <KpiBand
      kpis={[
        { label: t("Seats used"), value: String(used) },
        {
          label: t("Seats left"),
          value: left === undefined ? t("No limit") : String(left),
          hint:
            left === undefined
              ? t("The plan sets no seat cap.")
              : t("Invitations stop when this reaches 0."),
        },
      ]}
    />
  );
}
