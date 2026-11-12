import { Suspense } from "react";

import {
  StoreProduct,
  StoreProductSkeleton,
} from "@/features/store/components/store-product";

// The skeleton paints at once; the product streams in.
export const instant = true;

export default function StoreProductPage({
  params,
}: PageProps<"/[locale]/store/[org]/[product]">) {
  return (
    <Suspense fallback={<StoreProductSkeleton />}>
      {params.then(({ org, product }) => (
        <StoreProduct slug={org} productSlug={product} />
      ))}
    </Suspense>
  );
}
