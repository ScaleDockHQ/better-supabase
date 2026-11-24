import { getExtracted } from "next-intl/server";

import { Badge } from "@/components/reui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { Link } from "@/i18n/navigation";

import type { RecordSubject } from "../record-subject";

import { getRecordRuns } from "../records-queries";

/**
 * Render inside `<Suspense>`: the workflow runs started for a record, with
 * their status, each linking to the run. Renders nothing without
 * `workflows.read`.
 */
// skeleton: RecordSectionSkeleton in the record detail kit, rendered by the caller
export async function RecordWorkflows({ subject }: { subject: RecordSubject }) {
  const [t, permissions] = await Promise.all([
    getExtracted("records"),
    getPermissions(),
  ]);

  if (!can(permissions, "workflows.read")) {
    return null;
  }

  const runs = await getRecordRuns(subject);

  return (
    <Card size="sm" id="workflows">
      <CardHeader>
        <CardTitle>{t("Workflow progress")}</CardTitle>
        <CardDescription>{t("Runs started for this record.")}</CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-2">
        {runs.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            {t("No workflow has run for this record.")}
          </p>
        ) : (
          runs.map((run) => (
            <Link
              key={run.id}
              href={`/workflows/runs/${run.id}`}
              className="flex items-center gap-2 text-sm hover:underline"
            >
              <span className="min-w-0 flex-1 truncate">{run.definition}</span>
              <Badge variant="secondary">{run.status}</Badge>
            </Link>
          ))
        )}
      </CardContent>
    </Card>
  );
}
