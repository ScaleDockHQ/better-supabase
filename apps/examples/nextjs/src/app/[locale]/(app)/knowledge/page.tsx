import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { AddDocumentForm } from "@/features/knowledge/components/add-document-form";
import {
  DocumentList,
  DocumentListSkeleton,
} from "@/features/knowledge/components/document-list";
import { SearchForm } from "@/features/knowledge/components/search-form";

export const instant = true;

export default function KnowledgePage() {
  const t = useExtracted("knowledge");
  return (
    <>
      <PageHeader
        title={t("Knowledge")}
        description={t(
          "Documents on the knowledge block, chunked and embedded after you add them. The assistant searches them with a tool.",
        )}
      />
      <section className="space-y-3">
        <h2 className="text-sm font-medium">{t("Add a document")}</h2>
        <AddDocumentForm />
      </section>
      <section className="space-y-3">
        <h2 className="text-sm font-medium">{t("Documents")}</h2>
        <Suspense fallback={<DocumentListSkeleton />}>
          <DocumentList />
        </Suspense>
      </section>
      <section className="space-y-3">
        <h2 className="text-sm font-medium">{t("Search")}</h2>
        <SearchForm />
      </section>
    </>
  );
}
