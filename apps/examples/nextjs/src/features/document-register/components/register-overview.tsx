import { getExtracted } from "next-intl/server";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import { PeopleLoadError } from "@/features/people/components/people-load-error";
import { pageBlockRows } from "@/lib/block-list";

import { registerList, registerSpec } from "../document-register-list";
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
      initial={pageBlockRows(
        registerList,
        registerSpec,
        register.data,
        registerList.defaults,
      )}
      types={[...new Set(register.data.map((row) => row.type))].toSorted()}
    />
  );
}

export function RegisterOverviewSkeleton() {
  return <RecordListSkeleton rows={5} />;
}
