import { PackageCheckIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { refresh } from "next/cache";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
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
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { getMaterialRequirements } from "../manufacturing-queries";
import {
  CreateFromRequirementsButton,
  MaterialRequirementsGrid,
} from "./material-requirements-grid";

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

/** Render inside `<Suspense>`: the shortages over the next 30 days. */
export async function MaterialRequirementsSection() {
  const [t, permissions, requirements] = await Promise.all([
    getExtracted("production"),
    getPermissions(),
    getMaterialRequirements(),
  ]);

  if (requirements.kind === "no-organization") {
    return null;
  }

  const canPlan =
    requirements.kind === "ok" &&
    requirements.data.length > 0 &&
    can(permissions, "manufacturing.write");

  return (
    <Frame spacing="sm">
      <FrameHeader className="flex-row items-start justify-between gap-4">
        <div className="flex flex-col gap-0.5">
          <FrameTitle>{t("Material requirements")}</FrameTitle>
          <FrameDescription>
            {t(
              "What to produce or buy over the next 30 days to bring each item back to its reorder point, after stock, incoming receipts and open production orders.",
            )}
          </FrameDescription>
        </div>
        {canPlan ? <CreateFromRequirementsButton /> : null}
      </FrameHeader>
      <FramePanel>
        {requirements.kind === "error" ? (
          <Alert variant="destructive">
            <TriangleAlertIcon />
            <AlertTitle>{t("The requirements didn't load")}</AlertTitle>
            <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
            <AlertAction>
              <form action={retry}>
                <Button size="sm" variant="outline" type="submit">
                  {t("Retry")}
                </Button>
              </form>
            </AlertAction>
          </Alert>
        ) : requirements.data.length === 0 ? (
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <PackageCheckIcon />
              </EmptyMedia>
              <EmptyTitle>{t("Nothing is short")}</EmptyTitle>
              <EmptyDescription>
                {t(
                  "Every item with a reorder point has enough stock and incoming orders for the next 30 days.",
                )}
              </EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <a
                className="text-sm underline underline-offset-4"
                href="https://bettersupabase.com/docs/blocks/manufacturing"
              >
                {t("Read the manufacturing guide")}
              </a>
            </EmptyContent>
          </Empty>
        ) : (
          <MaterialRequirementsGrid requirements={requirements.data} />
        )}
      </FramePanel>
    </Frame>
  );
}

export function MaterialRequirementsSkeleton() {
  return (
    <Frame spacing="sm" aria-busy="true">
      <FrameHeader className="gap-1">
        <Skeleton className="h-4 w-44" />
        <Skeleton className="h-4 w-96" />
      </FrameHeader>
      <FramePanel className="flex flex-col gap-2">
        {[0, 1, 2, 3, 4].map((row) => (
          <Skeleton key={row} className="h-8 w-full" />
        ))}
      </FramePanel>
    </Frame>
  );
}
