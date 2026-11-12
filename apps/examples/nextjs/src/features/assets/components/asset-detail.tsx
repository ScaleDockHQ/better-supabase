import type { ReactNode } from "react";

import { formatMoney, moneyFromJson } from "better-supabase/commerce";
import { getExtracted, getFormatter, getLocale } from "next-intl/server";
import { notFound } from "next/navigation";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { RecordSectionSkeleton } from "@/components/record-detail/record-section-states";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { getAsset, getAssetHistory } from "../assets-queries";
import { AssetActionsBar } from "./asset-actions-bar";
import { AssetStatusBadge } from "./asset-status";

export function AssetHistorySkeleton() {
  return <RecordSectionSkeleton rows={3} />;
}

export async function AssetHistory({ id }: { id: string }) {
  const [history, t, format, locale] = await Promise.all([
    getAssetHistory(id),
    getExtracted("assets"),
    getFormatter(),
    getLocale(),
  ]);

  return (
    <>
      <Card size="sm">
        <CardHeader>
          <CardTitle>{t("Assignments")}</CardTitle>
          <CardDescription>
            {t("Who held the asset, newest first.")}
          </CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-2 text-sm">
          {history.assignments.length === 0 ? (
            <p className="text-muted-foreground">
              {t("Nobody has held this asset yet.")}
            </p>
          ) : (
            history.assignments.map((row) => (
              <div key={row.id} className="flex justify-between gap-4">
                <span>
                  {row.assigneeType} {row.assigneeId.slice(0, 8)}
                  {row.note ? ` · ${row.note}` : ""}
                </span>
                <span className="text-muted-foreground">
                  {format.dateTime(new Date(row.assignedAt), {
                    dateStyle: "medium",
                  })}
                  {row.releasedAt === null ? ` · ${t("held now")}` : ""}
                </span>
              </div>
            ))
          )}
        </CardContent>
      </Card>
      <Card size="sm">
        <CardHeader>
          <CardTitle>{t("Depreciation")}</CardTitle>
          <CardDescription>
            {t("The months the asset has depreciated, oldest first.")}
          </CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-2 text-sm">
          {history.depreciations.length === 0 ? (
            <p className="text-muted-foreground">
              {t("No depreciation booked.")}
            </p>
          ) : (
            history.depreciations.map((row) => (
              <div key={row.id} className="flex justify-between gap-4">
                <span>
                  {format.dateTime(new Date(row.periodStart), {
                    month: "long",
                    year: "numeric",
                  })}
                </span>
                <span className="tabular-nums">
                  {formatMoney(moneyFromJson(row.amount), locale)}
                </span>
              </div>
            ))
          )}
        </CardContent>
      </Card>
    </>
  );
}

/** One asset: the head renders from the prefetch, the history after navigation. */
export async function AssetDetail({
  id,
  history,
}: {
  id: string;
  /** The page owns the boundary that holds this section back. */
  history: ReactNode;
}) {
  const [asset, permissions, t, format, locale] = await Promise.all([
    getAsset(id),
    getPermissions(),
    getExtracted("assets"),
    getFormatter(),
    getLocale(),
  ]);

  if (asset === null) {
    notFound();
  }

  const money = (value: typeof asset.cost) =>
    value ? formatMoney(moneyFromJson(value), locale) : "–";

  return (
    <RecordDetailFrame
      title={asset.name}
      description={
        asset.locationPath.length > 0
          ? asset.locationPath.join(" / ")
          : t("{kind}, not placed at a location", { kind: asset.kind })
      }
      status={<AssetStatusBadge status={asset.status} />}
      actions={
        <AssetActionsBar
          assetId={asset.id}
          status={asset.status}
          canManage={can(permissions, "assets.manage")}
          canAssign={asset.assigned && can(permissions, "assets.assign")}
        />
      }
      aside={
        <Card size="sm">
          <CardHeader>
            <CardTitle>{t("Value")}</CardTitle>
          </CardHeader>
          <CardContent className="grid grid-cols-2 gap-2 text-sm">
            <span className="text-muted-foreground">{t("Cost")}</span>
            <span className="text-right tabular-nums">{money(asset.cost)}</span>
            <span className="text-muted-foreground">{t("Book value")}</span>
            <span className="text-right tabular-nums">
              {money(asset.bookValue)}
            </span>
            <span className="text-muted-foreground">{t("Depreciated")}</span>
            <span className="text-right tabular-nums">
              {money(asset.accumulatedDepreciation)}
            </span>
            <span className="text-muted-foreground">{t("Serial number")}</span>
            <span className="text-right">{asset.serialNumber ?? "–"}</span>
            <span className="text-muted-foreground">{t("Added")}</span>
            <span className="text-right">
              {format.dateTime(new Date(asset.createdAt), {
                dateStyle: "medium",
              })}
            </span>
          </CardContent>
        </Card>
      }
    >
      {history}
    </RecordDetailFrame>
  );
}

export function AssetDetailSkeleton() {
  return (
    <div className="grid gap-6 lg:grid-cols-3" aria-busy="true">
      <div className="flex flex-col gap-6 lg:col-span-2">
        <Skeleton className="h-10 w-72" />
        <RecordSectionSkeleton rows={3} />
      </div>
      <RecordSectionSkeleton rows={4} />
    </div>
  );
}
