import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  ProjectPage,
  ProjectPageSkeleton,
} from "@/features/projects/components/project-page";
import { Link } from "@/i18n/navigation";

export const instant = true;

/** The back link is the static shell; the project streams in. */
export default function ProjectRecordPage({
  params,
}: PageProps<"/[locale]/projects/[id]">) {
  const t = useExtracted("projects");

  return (
    <>
      <Link
        href="/projects"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All projects")}
      </Link>
      <Suspense fallback={<ProjectPageSkeleton />}>
        <ProjectPage params={params} />
      </Suspense>
    </>
  );
}
