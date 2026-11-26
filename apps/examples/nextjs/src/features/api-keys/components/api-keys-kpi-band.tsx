import { getExtracted } from "next-intl/server";

import { KpiBand, KpiBandSkeleton } from "@/components/record-list/kpi-band";

import { getApiKeyCounts } from "../api-keys-queries";

/** Render inside `<Suspense>` with `ApiKeysKpiBandSkeleton`. */
export async function ApiKeysKpiBand() {
  const [counts, t] = await Promise.all([
    getApiKeyCounts(),
    getExtracted("apiKeys"),
  ]);

  if (counts === null) {
    return null;
  }

  return (
    <KpiBand
      kpis={[
        { label: t("Active keys"), value: String(counts.active) },
        { label: t("Rotating"), value: String(counts.grace) },
        { label: t("Never used"), value: String(counts.unused) },
        { label: t("Retired"), value: String(counts.retired) },
      ]}
    />
  );
}

export function ApiKeysKpiBandSkeleton() {
  return <KpiBandSkeleton />;
}
