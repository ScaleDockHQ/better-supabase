import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { buttonVariants } from "@/components/ui/button";
import {
  ProjectPortfolio,
  ProjectPortfolioSkeleton,
} from "@/features/projects/components/project-portfolio";
import { Link } from "@/i18n/navigation";

// The portfolio frame paints before the figures stream in.
export const instant = true;

export default function ProjectPortfolioPage() {
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
        {t("All tasks")}
      </Link>
      <PageHeader
        title={t("Portfolio")}
        description={t(
          "The hours tracked on every project, this week's utilization and what is left of each budget.",
        )}
      />
      <Suspense fallback={<ProjectPortfolioSkeleton />}>
        <ProjectPortfolio />
      </Suspense>
    </>
  );
}
