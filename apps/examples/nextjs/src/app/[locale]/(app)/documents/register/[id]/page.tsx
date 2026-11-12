import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  RegisterDetail,
  RegisterDetailSkeleton,
} from "@/features/document-register/components/register-detail";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { Link } from "@/i18n/navigation";

// The back link and the skeleton paint at once; the document streams in.
export const instant = true;

export default function RegisterDocumentPage({
  params,
}: PageProps<"/[locale]/documents/register/[id]">) {
  const t = useExtracted("documents");

  return (
    <>
      <Link
        href="/documents/register"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All documents")}
      </Link>
      <Suspense fallback={<RegisterDetailSkeleton />}>
        <PermissionGate permission="drive.read">
          {params.then(({ id }) => (
            <RegisterDetail id={id} />
          ))}
        </PermissionGate>
      </Suspense>
    </>
  );
}
