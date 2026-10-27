import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  DocumentEditorSkeleton,
  DocumentEditorView,
} from "@/features/documents/components/document-editor-view";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { Link } from "@/i18n/navigation";

/** The back link is the static shell; the editor streams in. */
export default function DocumentPage({
  params,
}: PageProps<"/[locale]/documents/[id]">) {
  const t = useExtracted("documents");

  return (
    <>
      <Link
        href="/documents"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All documents")}
      </Link>
      <Suspense fallback={<DocumentEditorSkeleton />}>
        <PermissionGate permission="documents.read">
          <DocumentEditorView params={params} />
        </PermissionGate>
      </Suspense>
    </>
  );
}
