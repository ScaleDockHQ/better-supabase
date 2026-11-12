import { getExtracted } from "next-intl/server";
import { forbidden, notFound } from "next/navigation";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { RecordSectionSkeleton } from "@/components/record-detail/record-section-states";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { PeopleLoadError } from "@/features/people/components/people-load-error";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { getTemplate } from "../document-templates-queries";
import { TemplateActiveBadge } from "./template-active-badge";
import { TemplateToggle } from "./template-toggle";

/** Render inside `<Suspense>`: one template with its body. */
export async function TemplateDetail({ id }: { id: string }) {
  const [t, permissions, loaded] = await Promise.all([
    getExtracted("documents"),
    getPermissions(),
    getTemplate(id),
  ]);

  if (!can(permissions, "document_templates.read")) {
    forbidden();
  }

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <PeopleLoadError title={t("This template didn't load")} />;
  }

  if (loaded.data === "not-found") {
    notFound();
  }

  const { row, body } = loaded.data;

  return (
    <RecordDetailFrame
      title={row.name}
      description={`${row.documentType} · v${row.version}${
        row.language ? ` · ${row.language}` : ""
      }`}
      status={<TemplateActiveBadge active={row.active} />}
      actions={
        can(permissions, "document_templates.manage") ? (
          <TemplateToggle id={row.id} active={row.active} />
        ) : null
      }
    >
      <Card size="sm">
        <CardHeader>
          <CardTitle>{t("Body")}</CardTitle>
        </CardHeader>
        <CardContent>
          <pre className="overflow-x-auto text-sm whitespace-pre-wrap">
            {body}
          </pre>
        </CardContent>
      </Card>
    </RecordDetailFrame>
  );
}

export function TemplateDetailSkeleton() {
  return (
    <div className="flex flex-col gap-6" aria-busy="true">
      <Skeleton className="h-12" />
      <RecordSectionSkeleton rows={3} />
    </div>
  );
}
