import { getExtracted } from "next-intl/server";

import { RecordBoundSections } from "@/components/record-detail/record-bound-sections";
import { Skeleton } from "@/components/ui/skeleton";
import { discussCase } from "@/features/composites/composites-actions";
import { ActionDialog } from "@/features/sales/components/action-dialog";

export function CaseDiscussionSkeleton() {
  return <Skeleton className="h-40 rounded-xl" aria-busy="true" />;
}

/**
 * The discussion of a case, with a dialog that posts a comment through
 * `collaboration.discuss`.
 */
export async function CaseDiscussion({ id }: { id: string }) {
  const t = await getExtracted("cases");

  return (
    <div className="flex flex-col gap-4">
      <div className="flex justify-end">
        <ActionDialog
          action={discussCase}
          title={t("Discuss this case")}
          description={t("The comment appears in the case discussion below.")}
          trigger={t("Discuss")}
          submitLabel={t("Post comment")}
          successMessage={t("Comment posted")}
          variant="outline"
          hidden={{ caseId: id }}
          fields={[
            {
              name: "comment",
              label: t("Comment"),
              kind: "textarea",
              required: true,
            },
          ]}
        />
      </div>
      <RecordBoundSections
        subject={{ type: "case", id }}
        sections={["discussion", "history"]}
      />
    </div>
  );
}
