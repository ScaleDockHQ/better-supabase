import { getExtracted } from "next-intl/server";
import { notFound } from "next/navigation";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { Skeleton } from "@/components/ui/skeleton";

import { getPrompt } from "../prompts-queries";
import { PromptEditor } from "./prompt-editor";
import { PromptVersions } from "./prompt-versions";

/** Render inside `<Suspense>`: reads the `name` param and the prompt's versions. */
export async function PromptDetail({ name }: { name: string }) {
  const [prompt, t] = await Promise.all([
    getPrompt(name),
    getExtracted("prompts"),
  ]);

  if (prompt === undefined) {
    notFound();
  }

  const latest = prompt.versions[0];

  return (
    <RecordDetailFrame
      title={prompt.name}
      description={t(
        "Each save is a new version; a label decides which one is live.",
      )}
      aside={<PromptVersions name={prompt.name} versions={prompt.versions} />}
    >
      <PromptEditor
        name={prompt.name}
        initial={latest?.template ?? ""}
        next={(latest?.version ?? 0) + 1}
      />
    </RecordDetailFrame>
  );
}

export function PromptDetailSkeleton() {
  return (
    <div className="grid items-start gap-6 lg:grid-cols-3" aria-busy="true">
      <div className="flex flex-col gap-4 lg:col-span-2">
        <Skeleton className="h-8 w-64" />
        <Skeleton className="h-64 w-full" />
      </div>
      <Skeleton className="h-64 w-full" />
    </div>
  );
}
