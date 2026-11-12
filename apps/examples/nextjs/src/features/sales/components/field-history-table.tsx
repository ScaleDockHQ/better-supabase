import { getExtracted } from "next-intl/server";

import { CrmLoadError } from "@/features/crm/components/crm-load-error";
import { settle } from "@/features/crm/crm-queries";

import { loadFieldHistory } from "../automation/automation-queries";
import { loadMemberOptions } from "../member/member-queries";
import { DetailTable } from "./detail-table";
import { dateFormatter } from "./overview-support";

/** The tracked column changes of a company or a deal, newest first. */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function FieldHistoryTable({
  type,
  id,
}: {
  type: "company" | "deal";
  id: string;
}) {
  const [t, loaded, members, fmtDate] = await Promise.all([
    getExtracted("sales"),
    settle(() => loadFieldHistory(type, id)),
    loadMemberOptions(),
    dateFormatter(),
  ]);

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <CrmLoadError title={t("The field history didn't load")} />;
  }

  const nameOf = new Map(members.map((member) => [member.userId, member.name]));

  return (
    <DetailTable
      title={t("Field history")}
      description={t("Old and new values of the fields this record tracks.")}
      head={[t("Field"), t("Before"), t("After"), t("Changed by"), t("When")]}
      rows={loaded.data.map((change) => ({
        key: change.id,
        cells: [
          change.field,
          <span key="b" className="text-muted-foreground">
            {change.before}
          </span>,
          change.after,
          change.changedBy
            ? (nameOf.get(change.changedBy) ?? change.changedBy)
            : "–",
          fmtDate(change.changedAt),
        ],
      }))}
      emptyTitle={t("No changes recorded")}
    />
  );
}
