import { Suspense } from "react";

import {
  StatusPage,
  StatusPageSkeleton,
} from "@/features/status/components/status-page";

export default function StatusRoute({
  params,
}: PageProps<"/[locale]/status/[slug]">) {
  return (
    <Suspense fallback={<StatusPageSkeleton />}>
      {params.then(({ slug }) => (
        <StatusPage slug={slug} />
      ))}
    </Suspense>
  );
}
