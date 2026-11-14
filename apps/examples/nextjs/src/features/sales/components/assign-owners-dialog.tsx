import { getExtracted } from "next-intl/server";

import { settle } from "@/features/crm/crm-queries";
import { getAuthors } from "@/features/records/records-queries";

import { loadDeals } from "../pipeline/pipeline-queries";
import { AssignOwnersForm } from "./assign-owners-form";
import { holds } from "./overview-support";

// skeleton: the page renders it inside `<Suspense fallback={null}>`, so it has no frame to hold
/** The bulk owner button of the deal table, for callers who can write deals. */
export async function AssignOwnersDialog() {
  if (!(await holds("deals.write"))) {
    return null;
  }

  const [t, loaded, authors] = await Promise.all([
    getExtracted("sales"),
    settle(loadDeals),
    getAuthors(),
  ]);

  if (loaded.kind !== "ok" || !loaded.data) {
    return null;
  }

  const owners = Object.entries(authors).map(([value, label]) => ({
    value,
    label,
  }));

  if (owners.length === 0) {
    return null;
  }

  return (
    <div className="flex justify-end">
      <AssignOwnersForm
        owners={owners}
        unassigned={t("No owner")}
        deals={loaded.data.deals
          .filter((deal) => deal.category === "open")
          .map((deal) => ({
            id: deal.id,
            name: deal.name,
            owner:
              deal.ownerId === null ? null : (authors[deal.ownerId] ?? null),
          }))}
      />
    </div>
  );
}
