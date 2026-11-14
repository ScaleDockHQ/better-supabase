import { getExtracted } from "next-intl/server";
import { notFound } from "next/navigation";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { Fact } from "@/features/admin-lists/admin-detail-page";

import { getMarketplaceResource } from "../marketplace-queries";
import { resourceBadge } from "./marketplace-overview";

/** Render inside `<Suspense>`; the fallback is `ResourceDetailSkeleton`. */
export async function ResourceDetail({ externalId }: { externalId: string }) {
  const [found, t] = await Promise.all([
    getMarketplaceResource(externalId),
    getExtracted("marketplace"),
  ]);

  if (!found) {
    notFound();
  }

  const { installation, resource } = found;

  return (
    <RecordDetailFrame
      title={resource.name}
      description={resource.externalId}
      status={resourceBadge(resource.status, resource.status)}
    >
      <Card>
        <CardHeader>
          <CardTitle>{t("Resource")}</CardTitle>
          <CardDescription>
            {t("What Vercel provisioned for this installation.")}
          </CardDescription>
        </CardHeader>
        <CardContent>
          <dl className="grid gap-4 sm:grid-cols-2">
            <Fact label={t("Plan")}>{resource.planId ?? "-"}</Fact>
            <Fact label={t("Installation")}>
              {installation.configurationId}
            </Fact>
            <Fact label={t("Vercel team")}>{installation.teamId ?? "-"}</Fact>
          </dl>
        </CardContent>
      </Card>
    </RecordDetailFrame>
  );
}

export function ResourceDetailSkeleton() {
  return <Skeleton className="h-48 rounded-xl" aria-busy="true" />;
}
