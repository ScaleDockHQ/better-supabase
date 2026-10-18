import type { DataExportStatus } from "better-supabase/blocks/data-lifecycle";

import { ArchiveIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";
import { unstable_rethrow } from "next/navigation";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Badge, type BadgeProps } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardAction,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import { Link } from "@/i18n/navigation";

import { refreshPrivacy } from "../privacy-actions";
import {
  type ExportRow,
  loadPrivacy,
  type PrivacyData,
} from "../privacy-queries";
import {
  CancelDeletionButton,
  DeleteOrganizationButton,
  DownloadExportButton,
  RequestExportButton,
} from "./privacy-controls";

async function loadSettings(): Promise<
  { kind: "ok"; data: PrivacyData } | { kind: "error" }
> {
  try {
    return { kind: "ok", data: await loadPrivacy() };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}

const STATUS_VARIANT: Record<DataExportStatus, BadgeProps["variant"]> = {
  pending: "secondary",
  running: "info-light",
  ready: "success-light",
  failed: "destructive-light",
};

// #region recipe:data-export-delete
/**
 * Data exports for the caller and, with `organization.export`, for the
 * organization, each with its status and a download. Owners schedule the
 * organization's deletion here; account deletion stays on the security page.
 */
export async function PrivacySettings() {
  const [t, format, result] = await Promise.all([
    getExtracted("privacy"),
    getFormatter(),
    loadSettings(),
  ]);

  if (result.kind === "error") {
    return (
      <Alert variant="destructive" data-recipe="data-export-delete">
        <TriangleAlertIcon />
        <AlertTitle>{t("Your data settings could not be loaded")}</AlertTitle>
        <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
        <AlertAction>
          <form action={refreshPrivacy}>
            <Button size="sm" variant="outline" type="submit">
              {t("Retry")}
            </Button>
          </form>
        </AlertAction>
      </Alert>
    );
  }

  const { mine, organization, canDelete, purgeAfter } = result.data;

  const date = (value: string) =>
    format.dateTime(new Date(value), {
      dateStyle: "medium",
      timeStyle: "short",
    });

  const statusLabel = (status: DataExportStatus) => {
    switch (status) {
      case "pending": {
        return t("Queued");
      }

      case "running": {
        return t("Running");
      }

      case "ready": {
        return t("Ready");
      }

      case "failed": {
        return t("Failed");
      }

      default: {
        const unknown: never = status;

        return unknown;
      }
    }
  };

  const exportList = (
    rows: readonly ExportRow[],
    scope: "user" | "organization",
  ) =>
    rows.length === 0 ? (
      <Empty>
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <ArchiveIcon />
          </EmptyMedia>
          <EmptyTitle>{t("No exports yet")}</EmptyTitle>
          <EmptyDescription>
            {scope === "user"
              ? t("Export a copy of everything stored about you.")
              : t("Export a copy of the organization's data.")}
          </EmptyDescription>
        </EmptyHeader>
        <EmptyContent>
          <RequestExportButton scope={scope} />
        </EmptyContent>
      </Empty>
    ) : (
      <ul className="flex flex-col divide-y rounded-lg border">
        {rows.map((row) => (
          <li
            key={row.id}
            className="flex flex-wrap items-center justify-between gap-2 p-3"
          >
            <div className="flex flex-col gap-1">
              <div className="flex items-center gap-2">
                <span className="text-sm font-medium">
                  {date(row.requestedAt)}
                </span>
                <Badge variant={STATUS_VARIANT[row.status]}>
                  {statusLabel(row.status)}
                </Badge>
              </div>
              <span className="text-xs text-muted-foreground">
                {row.status === "failed"
                  ? (row.error ?? t("The export failed. Request a new one."))
                  : row.expiresAt
                    ? t("{count} files, available until {date}", {
                        count: String(row.files),
                        date: date(row.expiresAt),
                      })
                    : t("{count} files", { count: String(row.files) })}
              </span>
            </div>
            {row.status === "ready" ? (
              <DownloadExportButton id={row.id} />
            ) : null}
          </li>
        ))}
      </ul>
    );

  return (
    <div className="flex flex-col gap-6" data-recipe="data-export-delete">
      <Card>
        <CardHeader>
          <CardTitle>{t("Your data")}</CardTitle>
          <CardDescription>
            {t(
              "Download your profile, notifications and everything else stored about you.",
            )}
          </CardDescription>
          {mine.length > 0 ? (
            <CardAction>
              <RequestExportButton scope="user" variant="outline" />
            </CardAction>
          ) : null}
        </CardHeader>
        <CardContent>{exportList(mine, "user")}</CardContent>
      </Card>
      {organization ? (
        <Card>
          <CardHeader>
            <CardTitle>{t("Organization data")}</CardTitle>
            <CardDescription>
              {t("Download every record the organization owns.")}
            </CardDescription>
            {organization.length > 0 ? (
              <CardAction>
                <RequestExportButton scope="organization" variant="outline" />
              </CardAction>
            ) : null}
          </CardHeader>
          <CardContent>{exportList(organization, "organization")}</CardContent>
        </Card>
      ) : null}
      {canDelete || purgeAfter ? (
        <Card className="ring-destructive/30">
          <CardHeader>
            <CardTitle>{t("Delete organization")}</CardTitle>
            <CardDescription>
              {t(
                "Disables the organization now and purges its data after a 30 day grace period.",
              )}
            </CardDescription>
          </CardHeader>
          <CardContent>
            {purgeAfter ? (
              <Alert variant="destructive">
                <TriangleAlertIcon />
                <AlertTitle>{t("Deletion scheduled")}</AlertTitle>
                <AlertDescription>
                  {t("The organization's data is purged on {date}.", {
                    date: date(purgeAfter),
                  })}
                </AlertDescription>
                <AlertAction>
                  <CancelDeletionButton />
                </AlertAction>
              </Alert>
            ) : (
              <DeleteOrganizationButton />
            )}
          </CardContent>
        </Card>
      ) : null}
      <p className="text-sm text-muted-foreground">
        {t("To delete your own account, go to")}{" "}
        <Link
          href="/settings/security"
          className="text-foreground underline underline-offset-4"
        >
          {t("Security")}
        </Link>
      </p>
    </div>
  );
}
// #endregion recipe:data-export-delete

export function PrivacySettingsSkeleton() {
  return (
    <div className="flex flex-col gap-6" aria-busy="true">
      <Skeleton className="h-48 rounded-xl" />
      <Skeleton className="h-48 rounded-xl" />
    </div>
  );
}
