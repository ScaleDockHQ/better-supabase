import { TriangleAlertIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { refresh } from "next/cache";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";

import { getDocumentTarget } from "../documents-queries";
import { DocumentEditor } from "./document-editor";

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

/** Render inside `<Suspense>`: the customer's notes in the editor. */
export async function DocumentEditorView({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;

  const [view, t] = await Promise.all([
    getDocumentTarget(id),
    getExtracted("documents"),
  ]);

  if (view.kind === "no-organization") {
    return null;
  }

  if (view.kind === "error") {
    return (
      <Alert variant="destructive">
        <TriangleAlertIcon />
        <AlertTitle>{t("The document didn't load")}</AlertTitle>
        <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
        <AlertAction>
          <form action={retry}>
            <Button size="sm" variant="outline" type="submit">
              {t("Retry")}
            </Button>
          </form>
        </AlertAction>
      </Alert>
    );
  }

  return <DocumentEditor {...view.data} />;
}

export function DocumentEditorSkeleton() {
  return <Skeleton className="h-96 rounded-xl" aria-busy="true" />;
}
