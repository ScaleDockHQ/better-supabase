import { notFound } from "next/navigation";

import { getBuilderDetail } from "../builder-queries";
import { WorkflowEditorLazy } from "./workflow-editor-lazy";

// skeleton: BuilderEditorSkeleton lives in its own file because the lazy editor shares it
/** Render inside `<Suspense>`: reads the `definition` param. */
export async function BuilderEditor({ definition }: { definition: string }) {
  const detail = await getBuilderDetail(definition);

  if (detail === null) {
    notFound();
  }

  return (
    <>
      <h2 className="text-lg font-semibold">{detail.definition.name}</h2>
      <WorkflowEditorLazy detail={detail} />
    </>
  );
}
