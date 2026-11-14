import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  ClientDossier,
  ClientDossierSkeleton,
} from "@/features/care/components/client-dossier";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { Link } from "@/i18n/navigation";

/** The back link is the static shell; the client's dossier streams in. */
// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function ClientPage({
  params,
}: PageProps<"/[locale]/care/[clientId]">) {
  const t = useExtracted("care");

  return (
    <div className="flex flex-col gap-4">
      <Link
        href="/care"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All clients")}
      </Link>
      <Suspense fallback={<ClientDossierSkeleton />}>
        <PermissionGate permission="customers.read">
          {params.then(({ clientId }) => (
            <ClientDossier clientId={clientId} />
          ))}
        </PermissionGate>
      </Suspense>
    </div>
  );
}
