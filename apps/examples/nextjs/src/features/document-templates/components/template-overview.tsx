import { getExtracted } from "next-intl/server";
import { forbidden } from "next/navigation";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import { PeopleLoadError } from "@/features/people/components/people-load-error";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { getTemplates } from "../document-templates-queries";
import { AddStarterTemplateButton } from "./add-starter-template-button";
import { TemplateRecordList } from "./template-record-list";

/** Render inside `<Suspense>`: the organization's document templates. */
export async function TemplateOverview() {
  const [t, permissions, templates] = await Promise.all([
    getExtracted("documents"),
    getPermissions(),
    getTemplates(),
  ]);

  if (!can(permissions, "document_templates.read")) {
    forbidden();
  }

  if (templates.kind === "no-organization") {
    return null;
  }

  if (templates.kind === "error") {
    return <PeopleLoadError title={t("Templates didn't load")} />;
  }

  return (
    <div className="flex flex-col gap-4">
      {templates.data.items.length === 0 &&
      !templates.data.nextCursor &&
      can(permissions, "document_templates.manage") ? (
        <div className="flex justify-end">
          <AddStarterTemplateButton />
        </div>
      ) : null}
      <TemplateRecordList
        initial={templates.data}
        types={Object.keys(
          templates.data.facetCounts?.["type"] ?? {},
        ).toSorted()}
      />
    </div>
  );
}

export function TemplateOverviewSkeleton() {
  return <RecordListSkeleton rows={5} />;
}
