"use client";

import { formatMoney, money } from "better-supabase/commerce";
import { useAction } from "better-supabase/react";
import { ArrowRightIcon, HistoryIcon } from "lucide-react";
import { useExtracted, useFormatter, useLocale } from "next-intl";
import { toast } from "sonner";

import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
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
import { snapshotProjectVersions } from "@/lib/supabase/features/project/project-actions";
import { useErrorMessage } from "@/lib/use-error-message";

import type { ProjectHistoryField, ProjectVersion } from "../project-types";

import { restoreProjectFields } from "../project-actions";
import { PROJECT_HISTORY_FIELDS } from "../project-types";

// #region recipe:record-history

interface FieldChange {
  readonly field: ProjectHistoryField;
  readonly before: string | undefined;
  readonly after: string | undefined;
}

/**
 * The fields a version changed from the one before it; all of them for the
 * first.
 */
function changesOf(
  version: ProjectVersion,
  previous: ProjectVersion | undefined,
): readonly FieldChange[] {
  return PROJECT_HISTORY_FIELDS.flatMap((field) => {
    const after = version.fields[field];
    const before = previous?.fields[field];

    return previous !== undefined && before === after
      ? []
      : [{ field, before, after }];
  });
}

/**
 * The project's history: every version the snapshot trigger kept, with the
 * fields it changed. Restore writes one field of an older version back and
 * leaves the others as they are.
 */
export function ProjectHistory({
  projectId,
  versions,
  canSave,
  canRestore,
}: {
  projectId: string;
  versions: readonly ProjectVersion[];
  canSave: boolean;
  canRestore: boolean;
}) {
  const t = useExtracted("projects");

  return (
    <Card size="sm" data-recipe="record-history">
      <CardHeader>
        <CardTitle>{t("History")}</CardTitle>
        <CardDescription>
          {t("Each change to the name, budget or currency.")}
        </CardDescription>
      </CardHeader>
      <CardContent>
        {versions.length === 0 ? (
          <Empty className="border">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <HistoryIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No history yet")}</EmptyTitle>
              <EmptyDescription>
                {t("The next change to this project appears here.")}
              </EmptyDescription>
            </EmptyHeader>
            {canSave ? (
              <EmptyContent>
                <SaveVersionButton projectId={projectId} />
              </EmptyContent>
            ) : null}
          </Empty>
        ) : (
          <ol className="flex flex-col divide-y" data-testid="project-history">
            {versions.map((version, index) => (
              <VersionEntry
                key={version.id}
                projectId={projectId}
                version={version}
                changes={changesOf(version, versions[index + 1])}
                canRestore={canRestore && index > 0}
              />
            ))}
          </ol>
        )}
      </CardContent>
    </Card>
  );
}

function VersionEntry({
  projectId,
  version,
  changes,
  canRestore,
}: {
  projectId: string;
  version: ProjectVersion;
  changes: readonly FieldChange[];
  canRestore: boolean;
}) {
  const t = useExtracted("projects");
  const format = useFormatter();
  const locale = useLocale();
  const errorMessage = useErrorMessage();

  const restore = useAction(restoreProjectFields, {
    onSuccess: () => {
      toast.success(t("Field restored"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  const label = {
    name: t("Name"),
    budget_minor: t("Budget"),
    currency: t("Currency"),
  } as const satisfies Record<ProjectHistoryField, string>;

  const source = {
    manual: t("Saved"),
    auto: t("Edited"),
    restore: t("Restored"),
  } as const satisfies Record<ProjectVersion["source"], string>;

  const shown = (field: ProjectHistoryField, value: string | undefined) => {
    if (value === undefined) {
      return t("Empty");
    }

    return field === "budget_minor"
      ? formatMoney(
          money(BigInt(value), version.fields.currency ?? "EUR"),
          locale,
        )
      : value;
  };

  return (
    <li className="flex flex-col gap-2 py-3">
      <div className="flex items-center gap-2">
        <span className="text-sm font-medium">
          {t("Version {number}", { number: String(version.number) })}
        </span>
        <Badge variant="secondary">{source[version.source]}</Badge>
        <span className="ml-auto text-xs text-muted-foreground">
          {format.dateTime(version.createdAt, {
            dateStyle: "medium",
            timeStyle: "short",
          })}
        </span>
      </div>
      <dl className="flex flex-col gap-1">
        {changes.map((change) => (
          <div key={change.field} className="flex items-center gap-2 text-sm">
            <dt className="w-20 shrink-0 text-muted-foreground">
              {label[change.field]}
            </dt>
            <dd className="flex min-w-0 flex-1 items-center gap-1">
              {change.before === undefined ? null : (
                <>
                  <span className="truncate text-muted-foreground line-through">
                    {shown(change.field, change.before)}
                  </span>
                  <ArrowRightIcon className="size-3 shrink-0 text-muted-foreground" />
                </>
              )}
              <span className="truncate">
                {shown(change.field, change.after)}
              </span>
            </dd>
            {canRestore ? (
              <Button
                size="xs"
                variant="ghost"
                disabled={restore.pending}
                aria-label={t("Restore {field} from version {number}", {
                  field: label[change.field],
                  number: String(version.number),
                })}
                onClick={() => {
                  void restore.run({
                    projectId,
                    versionId: version.id,
                    fields: [change.field],
                  });
                }}
              >
                {t("Restore")}
              </Button>
            ) : null}
          </div>
        ))}
      </dl>
    </li>
  );
}

function SaveVersionButton({ projectId }: { projectId: string }) {
  const t = useExtracted("projects");
  const errorMessage = useErrorMessage();

  const save = useAction(snapshotProjectVersions, {
    onSuccess: () => {
      toast.success(t("Version saved"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <Button
      size="sm"
      variant="outline"
      disabled={save.pending}
      onClick={() => {
        void save.run({ id: projectId, input: {} });
      }}
    >
      <HistoryIcon />
      {t("Save a version")}
    </Button>
  );
}

// #endregion recipe:record-history
