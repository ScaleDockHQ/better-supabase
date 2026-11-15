import { getExtracted } from "next-intl/server";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import { PeopleLoadError } from "@/features/people/components/people-load-error";

import { getRegister } from "../document-register-queries";
import { RegisterRecordList } from "./register-record-list";

/** Render inside `<Suspense>`: the organization's controlled documents. */
export async function RegisterOverview() {
  const [t, register] = await Promise.all([
    getExtracted("documents"),
    getRegister(),
  ]);

  if (register.kind === "no-organization") {
    return null;
  }

  if (register.kind === "error") {
    return <PeopleLoadError title={t("The register didn't load")} />;
  }

  return (
    <RegisterRecordList
      initial={register.data}
      types={Object.keys(register.data.facetCounts?.["type"] ?? {}).toSorted()}
    />
  );
}

export function RegisterOverviewSkeleton() {
  return <RecordListSkeleton rows={5} />;
}
