import { getExtracted } from "next-intl/server";
import { notFound } from "next/navigation";

import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Skeleton } from "@/components/ui/skeleton";

import type { EvalParams } from "../evals-search-params";

import { getEvalWorkspace } from "../evals-queries";
import { isScripted } from "../evals-task";
import { EvalItemsCard } from "./eval-items-card";
import { EvalResults } from "./eval-results";
import { EvalRunForm } from "./eval-run-form";
import { EvalRunsCard } from "./eval-runs-card";

/**
 * Render inside `<Suspense>`: reads the `name` param and the URL's run: the
 * dataset, the runs with their trend and the selected run's results.
 */
export async function EvalWorkspace({
  name,
  filters,
}: {
  name: string;
  filters: Promise<EvalParams>;
}) {
  const [workspace, t] = await Promise.all([
    filters.then((resolved) => getEvalWorkspace(name, resolved)),
    getExtracted("evals"),
  ]);

  if (workspace === undefined) {
    notFound();
  }

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-1">
        <h1 className="text-2xl font-semibold tracking-tight">{name}</h1>
        <p className="text-sm text-muted-foreground">
          {t(
            "Run the dataset against a prompt version and compare the pass rate with earlier runs.",
          )}
        </p>
      </div>
      {isScripted() ? (
        <Alert>
          <AlertTitle>{t("Scripted runs")}</AlertTitle>
          <AlertDescription>
            {t(
              "No AI Gateway key is set, so a run answers from a script and is recorded as scripted. The pass rate measures the script, not a model.",
            )}
          </AlertDescription>
        </Alert>
      ) : null}
      <EvalRunForm
        name={name}
        versions={workspace.versions}
        items={workspace.items.length}
      />
      <div className="grid items-start gap-6 lg:grid-cols-2">
        <EvalItemsCard name={name} items={workspace.items} />
        <EvalRunsCard
          name={name}
          runs={workspace.runs}
          selectedId={workspace.selected?.id}
        />
      </div>
      {workspace.selected === undefined ? null : (
        <EvalResults
          results={workspace.results}
          comparison={workspace.comparison}
          failedOnly={await filters.then((resolved) => resolved.failed)}
        />
      )}
    </div>
  );
}

export function EvalWorkspaceSkeleton() {
  return (
    <div className="flex flex-col gap-6" aria-busy="true">
      <Skeleton className="h-8 w-64" />
      <Skeleton className="h-8 w-96" />
      <div className="grid gap-6 lg:grid-cols-2">
        <Skeleton className="h-72 w-full" />
        <Skeleton className="h-72 w-full" />
      </div>
    </div>
  );
}
