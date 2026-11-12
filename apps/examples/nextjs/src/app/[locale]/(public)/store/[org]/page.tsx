import { Suspense } from "react";

import {
  StoreCatalog,
  StoreCatalogSkeleton,
} from "@/features/store/components/store-catalog";

// The shell and the skeleton paint at once; the products stream in.
export const instant = true;

export default function StorePage({
  params,
  searchParams,
}: PageProps<"/[locale]/store/[org]">) {
  return (
    <Suspense fallback={<StoreCatalogSkeleton />}>
      {params.then(({ org }) => (
        <StoreCatalog slug={org} urlQuery={searchParams} />
      ))}
    </Suspense>
  );
}
