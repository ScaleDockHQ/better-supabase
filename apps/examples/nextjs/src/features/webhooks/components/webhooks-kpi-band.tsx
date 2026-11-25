import { getExtracted } from "next-intl/server";

import { KpiBand, KpiBandSkeleton } from "@/components/record-list/kpi-band";

import { getWebhooks } from "../webhooks-queries";

/** Render inside `<Suspense>` with `WebhooksKpiBandSkeleton`. */
export async function WebhooksKpiBand() {
  const [overview, t] = await Promise.all([
    getWebhooks(),
    getExtracted("webhooks"),
  ]);

  if (overview === null) {
    return null;
  }

  const { endpoints, deliveries } = overview;

  return (
    <KpiBand
      kpis={[
        { label: t("Endpoints"), value: String(endpoints.length) },
        {
          label: t("Failing or off"),
          value: String(
            endpoints.filter(
              (endpoint) => !endpoint.enabled || endpoint.failingSince !== null,
            ).length,
          ),
        },
        {
          label: t("Delivered"),
          value: String(
            deliveries.filter((row) => row.status === "succeeded").length,
          ),
          hint: t("Of the latest {count, number} deliveries", {
            count: deliveries.length,
          }),
        },
        {
          label: t("Retrying or dead"),
          value: String(
            deliveries.filter(
              (row) => row.status === "retrying" || row.status === "dead",
            ).length,
          ),
        },
      ]}
    />
  );
}

export function WebhooksKpiBandSkeleton() {
  return <KpiBandSkeleton />;
}
