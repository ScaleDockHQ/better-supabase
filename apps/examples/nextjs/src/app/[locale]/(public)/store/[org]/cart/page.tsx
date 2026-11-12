import { Suspense } from "react";

import {
  StoreCartViewSkeleton,
  StoreCartView,
} from "@/features/store/components/store-cart-view";

// The skeleton paints at once; the cart reads its cookie behind the boundary.
export const instant = true;

export default function StoreCartPage({
  params,
}: PageProps<"/[locale]/store/[org]/cart">) {
  return (
    <Suspense fallback={<StoreCartViewSkeleton />}>
      {params.then(({ org }) => (
        <StoreCartView slug={org} />
      ))}
    </Suspense>
  );
}
