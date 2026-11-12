import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  IncidentDetail,
  IncidentDetailSkeleton,
} from "@/features/incidents/components/incident-detail";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { Link } from "@/i18n/navigation";

export const instant = true;

export default function IncidentPage({
  params,
}: PageProps<"/[locale]/incidents/[id]">) {
  const t = useExtracted("incidents");

  return (
    <>
      <Link
        href="/incidents"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All incidents")}
      </Link>
      <Suspense fallback={<IncidentDetailSkeleton />}>
        <PermissionGate permission="incidents.read">
          {params.then(({ id }) => (
            <IncidentDetail id={id} />
          ))}
        </PermissionGate>
      </Suspense>
    </>
  );
}
