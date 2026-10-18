import { TableIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { buttonVariants } from "@/components/ui/button";
import {
  WorkBoard,
  WorkBoardSkeleton,
} from "@/features/work/components/work-board";
import { Link } from "@/i18n/navigation";

export const instant = true;

export default function WorkPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const t = useExtracted("work");

  return (
    <>
      <PageHeader
        title={t("Work")}
        description={t(
          "Work items by state. Moves follow the workflow's allowed transitions.",
        )}
        actions={
          <Link
            href="/work/grid"
            className={buttonVariants({ variant: "outline", size: "sm" })}
          >
            <TableIcon />
            {t("Grid")}
          </Link>
        }
      />
      <Suspense fallback={<WorkBoardSkeleton />}>
        <WorkBoard searchParams={searchParams} />
      </Suspense>
    </>
  );
}
