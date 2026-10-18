import { Suspense } from "react";

import {
  SharedCustomerCard,
  SharedCustomerCardSkeleton,
} from "@/features/customers/components/shared-customer-card";

export const instant = true;

export default function SharePage({
  params,
}: PageProps<"/[locale]/share/[token]">) {
  return (
    <Suspense fallback={<SharedCustomerCardSkeleton />}>
      <SharedCustomerCard params={params} />
    </Suspense>
  );
}
