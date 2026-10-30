import { MousePointerClickIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { getExtracted } from "next-intl/server";
import { connection } from "next/server";
import { Suspense } from "react";
import * as v from "valibot";

import { PageHeader } from "@/components/page-header";
import { Frame, FramePanel } from "@/components/reui/frame";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import {
  InspectionProgramCalendar,
  InspectionProgramCalendarSkeleton,
} from "@/features/inspections/components/inspection-program-calendar";
import {
  InspectionRun,
  InspectionRunSkeleton,
} from "@/features/inspections/components/inspection-run";
import {
  getInspectionCalendar,
  getInspectionRun,
} from "@/features/inspections/inspections-queries";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

const InspectionParam = v.pipe(v.string(), v.uuid());

async function Calendar() {
  return <InspectionProgramCalendar state={await getInspectionCalendar()} />;
}

async function Run({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const [t, query, permissions] = await Promise.all([
    getExtracted("inspections"),
    searchParams,
    getPermissions(),
    connection(),
  ]);

  const picked = v.safeParse(InspectionParam, query["inspection"]);

  if (!picked.success) {
    return (
      <Frame spacing="sm">
        <FramePanel>
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <MousePointerClickIcon />
              </EmptyMedia>
              <EmptyTitle>{t("Pick an inspection")}</EmptyTitle>
              <EmptyDescription>
                {t(
                  "Open an inspection in the programme to see its team, checklist and findings.",
                )}
              </EmptyDescription>
            </EmptyHeader>
          </Empty>
        </FramePanel>
      </Frame>
    );
  }

  return (
    <InspectionRun
      state={await getInspectionRun(picked.output)}
      canWork={can(permissions, "inspections.write")}
    />
  );
}

export default function InspectionsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const t = useExtracted("inspections");

  return (
    <>
      <PageHeader
        title={t("Audits and inspections")}
        description={t(
          "The audit programme with each inspection's status, and the findings of the one you open, each nonconformity with its case.",
        )}
      />
      <Suspense fallback={<InspectionProgramCalendarSkeleton />}>
        <PermissionGate permission="inspections.read">
          <Calendar />
        </PermissionGate>
      </Suspense>
      <Suspense fallback={<InspectionRunSkeleton />}>
        <PermissionGate permission="inspections.read">
          <Run searchParams={searchParams} />
        </PermissionGate>
      </Suspense>
    </>
  );
}
