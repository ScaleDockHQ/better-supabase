import { getExtracted } from "next-intl/server";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import { PeopleLoadError } from "@/features/people/components/people-load-error";
import { pageBlockRows } from "@/lib/block-list";

import { getQualificationTypes } from "../qualifications-queries";
import {
  qualificationTypeList,
  qualificationTypeSpec,
} from "../qualifications-types-list";
import { QualificationTypeRecordList } from "./qualification-type-record-list";

/** Render inside `<Suspense>`: the organization's qualification types. */
export async function QualificationTypeOverview() {
  const [t, types] = await Promise.all([
    getExtracted("qualifications"),
    getQualificationTypes(),
  ]);

  if (types.kind === "no-organization") {
    return null;
  }

  if (types.kind === "error") {
    return <PeopleLoadError title={t("Qualification types didn't load")} />;
  }

  return (
    <QualificationTypeRecordList
      initial={pageBlockRows(
        qualificationTypeList,
        qualificationTypeSpec,
        types.data,
        qualificationTypeList.defaults,
      )}
    />
  );
}

export function QualificationTypeOverviewSkeleton() {
  return <RecordListSkeleton rows={4} />;
}
