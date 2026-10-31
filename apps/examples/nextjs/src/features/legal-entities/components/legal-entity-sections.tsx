import { LandmarkIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { refresh } from "next/cache";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import {
  Frame,
  FrameDescription,
  FrameHeader,
  FramePanel,
  FrameTitle,
} from "@/components/reui/frame";
import { Button } from "@/components/ui/button";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { settle } from "@/features/shop/shop-queries";

import { getLegalEntities } from "../legal-entities-queries";

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

/** Render inside `<Suspense>`: the organization's legal entities. */
export async function LegalEntityListSection() {
  const t = await getExtracted("legal-entities");
  const entities = await settle(getLegalEntities);

  if (entities.kind === "no-organization") {
    return null;
  }

  return (
    <Frame spacing="sm">
      <FrameHeader className="gap-0.5">
        <FrameTitle>{t("Legal entities")}</FrameTitle>
        <FrameDescription>
          {t(
            "Records without a legal entity belong to the default one. Settings fall back from the entity to the organization.",
          )}
        </FrameDescription>
      </FrameHeader>
      <FramePanel>
        {entities.kind === "error" ? (
          <Alert variant="destructive">
            <TriangleAlertIcon />
            <AlertTitle>{t("The legal entities didn't load")}</AlertTitle>
            <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
            <AlertAction>
              <form action={retry}>
                <Button size="sm" variant="outline" type="submit">
                  {t("Retry")}
                </Button>
              </form>
            </AlertAction>
          </Alert>
        ) : entities.data.length === 0 ? (
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <LandmarkIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No legal entities")}</EmptyTitle>
              <EmptyDescription>
                {t(
                  "A single-company organization needs none. Add one through the API when you invoice from several companies.",
                )}
              </EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <a
                className="text-sm underline underline-offset-4"
                href="https://bettersupabase.com/docs/blocks/legal-entities"
              >
                {t("Read the legal entities guide")}
              </a>
            </EmptyContent>
          </Empty>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("Code")}</TableHead>
                <TableHead>{t("Name")}</TableHead>
                <TableHead>{t("VAT number")}</TableHead>
                <TableHead>{t("Currency")}</TableHead>
                <TableHead>{t("Tax period")}</TableHead>
                <TableHead>{t("Status")}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {entities.data.map((entity) => (
                <TableRow key={entity.id}>
                  <TableCell className="text-sm font-medium">
                    {entity.code}
                  </TableCell>
                  <TableCell className="text-sm">{entity.name}</TableCell>
                  <TableCell className="text-sm">
                    {entity.vatNumber ?? "-"}
                  </TableCell>
                  <TableCell className="text-sm">
                    {entity.defaultCurrency ?? "-"}
                  </TableCell>
                  <TableCell className="text-sm">
                    {entity.taxPeriod === "monthly"
                      ? t("Monthly")
                      : t("Quarterly")}
                  </TableCell>
                  <TableCell>
                    <div className="flex gap-1">
                      {entity.isDefault ? (
                        <Badge variant="success-light">{t("Default")}</Badge>
                      ) : null}
                      {entity.archived ? (
                        <Badge variant="outline">{t("Archived")}</Badge>
                      ) : null}
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </FramePanel>
    </Frame>
  );
}

export function LegalEntityListSkeleton() {
  return (
    <Frame spacing="sm" aria-busy="true">
      <FrameHeader className="gap-1">
        <Skeleton className="h-4 w-36" />
        <Skeleton className="h-4 w-96" />
      </FrameHeader>
      <FramePanel className="flex flex-col gap-2">
        {[0, 1, 2].map((row) => (
          <Skeleton key={row} className="h-8 w-full" />
        ))}
      </FramePanel>
    </Frame>
  );
}
