import { notFound } from "next/navigation";

import { Skeleton } from "@/components/ui/skeleton";

import { getBuilderDetail } from "../builder-queries";
import { WorkflowCanvas } from "./workflow-canvas";

/** Render inside `<Suspense>`: reads the `definition` param. */
export async function BuilderEditor({
  params,
}: {
  params: Promise<{ definition: string }>;
}) {
  const { definition } = await params;
  const detail = await getBuilderDetail(definition);
  if (detail === null) notFound();
  return (
    <>
      <h2 className="text-lg font-semibold">{detail.definition.name}</h2>
      <WorkflowCanvas detail={detail} />
    </>
  );
}

export function BuilderEditorSkeleton() {
  return <Skeleton className="h-160 w-full" aria-busy="true" />;
}
