import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  DocumentEditorViewSkeleton,
  DocumentEditorView,
} from "@/features/documents/components/document-editor-view";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { Link } from "@/i18n/navigation";

/** The back link is the static shell; the editor streams in. */
// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

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
      <Suspense fallback={<DocumentEditorViewSkeleton />}>
        <PermissionGate permission="documents.read">
          {params.then(({ id }) => (
            <DocumentEditorView id={id} />
          ))}
        </PermissionGate>
      </Suspense>
    </>
  );
}
