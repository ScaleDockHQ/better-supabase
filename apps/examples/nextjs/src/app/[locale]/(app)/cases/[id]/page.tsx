import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  CaseDiscussion,
  CaseDiscussionSkeleton,
} from "@/features/cases/components/case-discussion";
import {
  CaseDetailSection,
  CaseDetailSectionSkeleton,
} from "@/features/cases/components/case-sections";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { Link } from "@/i18n/navigation";

export const instant = true;

export default function CasePage({
  params,
}: PageProps<"/[locale]/cases/[id]">) {
  const t = useExtracted("cases");

  return (
    <>
      <Link
        href="/cases?view=table"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All cases")}
      </Link>
      <Suspense fallback={<CaseDetailSectionSkeleton />}>
        <PermissionGate permission="cases.read">
          {params.then(({ id }) => (
            <CaseDetailSection query={{ case: id }} />
          ))}
        </PermissionGate>
      </Suspense>
      <Suspense fallback={<CaseDiscussionSkeleton />}>
        <PermissionGate permission="cases.read">
          {params.then(({ id }) => (
            <CaseDiscussion id={id} />
          ))}
        </PermissionGate>
      </Suspense>
    </>
  );
}
