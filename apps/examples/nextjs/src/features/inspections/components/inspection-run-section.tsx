import { MousePointerClickIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { io } from "next/cache";
import * as v from "valibot";

import { Frame, FramePanel } from "@/components/reui/frame";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { InspectionRun } from "@/features/inspections/components/inspection-run";
import { getInspectionRun } from "@/features/inspections/inspections-queries";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

const InspectionParam = v.pipe(v.string(), v.uuid());

// skeleton: the page passes the wrapped component's own skeleton to <Suspense>
export async function InspectionRunSection({
  query,
}: {
  query: Record<string, string | string[] | undefined>;
}) {
  const [t, permissions] = await Promise.all([
    getExtracted("inspections"),
    getPermissions(),
    io(),
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
