import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  EmployeeDetail,
  EmployeeDetailSkeleton,
} from "@/features/people/components/employee-detail";
import { Link } from "@/i18n/navigation";

// The back link and the skeleton paint at once; the employee streams in.
export const instant = true;

export default function EmployeePage({
  params,
}: PageProps<"/[locale]/people/[id]">) {
  const t = useExtracted("people");

  return (
    <>
      <Link
        href="/people"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All people")}
      </Link>
      <Suspense fallback={<EmployeeDetailSkeleton />}>
        {params.then(({ id }) => (
          <EmployeeDetail id={id} />
        ))}
      </Suspense>
    </>
  );
}
