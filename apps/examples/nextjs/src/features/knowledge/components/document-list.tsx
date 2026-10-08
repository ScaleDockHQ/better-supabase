import { Skeleton } from "@/components/ui/skeleton";

import { getDocuments } from "../knowledge-queries";
import { DocumentTable } from "./document-table";

/** Render inside `<Suspense>`. */
export async function DocumentList() {
  const documents = await getDocuments();
  return <DocumentTable documents={documents} />;
}

export function DocumentListSkeleton() {
  return <Skeleton className="h-32 w-full rounded-xl" />;
}
