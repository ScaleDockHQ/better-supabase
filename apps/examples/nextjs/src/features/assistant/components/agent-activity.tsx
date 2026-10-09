import { ActivityIcon, InboxIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";

import { Badge } from "@/components/ui/badge";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import { Link } from "@/i18n/navigation";

import { getActivity } from "../assistant-queries";
import { ApprovalButtons } from "./approval-buttons";

/** Render inside `<Suspense>`: the approval inbox, then the latest runs with their steps. */
export async function AgentActivity() {
  const [{ runs, approvals }, t, format] = await Promise.all([
    getActivity(),
    getExtracted("assistant"),
    getFormatter(),
  ]);
  const when = (iso: string) =>
    format.dateTime(new Date(iso), { dateStyle: "medium", timeStyle: "short" });

  return (
    <div className="flex flex-col gap-6">
      <section className="flex flex-col gap-3" aria-labelledby="approvals">
        <h2 id="approvals" className="text-sm font-medium">
          {t("Waiting for approval")}
        </h2>
        {approvals.length === 0 ? (
          <Empty className="border">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <InboxIcon />
              </EmptyMedia>
              <EmptyTitle>{t("Nothing to approve")}</EmptyTitle>
              <EmptyDescription>
                {t("Tool calls that need your approval show up here.")}
              </EmptyDescription>
            </EmptyHeader>
          </Empty>
        ) : (
          <ul className="divide-y rounded-xl border">
            {approvals.map((approval) => (
              <li
                key={approval.approvalId}
                className="flex flex-col gap-2 px-4 py-3 text-sm"
              >
                <p className="flex flex-wrap items-center gap-2">
                  <span className="font-medium">{approval.tool}</span>
                  <Link
                    href={`/assistant/${approval.chatId}`}
                    className="text-muted-foreground underline"
                  >
                    {approval.chatTitle === ""
                      ? t("Untitled chat")
                      : approval.chatTitle}
                  </Link>
                  <span className="text-muted-foreground text-xs tabular-nums">
                    {when(approval.createdAt)}
                  </span>
                </p>
                <pre className="bg-muted overflow-x-auto rounded-md p-2 text-xs whitespace-pre-wrap">
                  {approval.input}
                </pre>
                <ApprovalButtons
                  chatId={approval.chatId}
                  approvalId={approval.approvalId}
                />
              </li>
            ))}
          </ul>
        )}
      </section>
      <section className="flex flex-col gap-3" aria-labelledby="runs">
        <h2 id="runs" className="text-sm font-medium">
          {t("Latest runs")}
        </h2>
        {runs.length === 0 ? (
          <Empty className="border">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <ActivityIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No runs yet")}</EmptyTitle>
              <EmptyDescription>
                {t("Every answer the assistant writes is a run.")}
              </EmptyDescription>
            </EmptyHeader>
          </Empty>
        ) : (
          <ul className="divide-y rounded-xl border">
            {runs.map((run) => (
              <li
                key={run.id}
                className="flex flex-col gap-2 px-4 py-3 text-sm"
              >
                <p className="flex flex-wrap items-center gap-2">
                  <Badge variant="outline">{run.status}</Badge>
                  <Badge variant="secondary">
                    {run.engine === "workflow" ? t("Durable") : t("Standard")}
                  </Badge>
                  <Link
                    href={`/assistant/${run.chatId}`}
                    className="flex-1 truncate underline"
                  >
                    {run.model ?? t("Default model")}
                  </Link>
                  <span className="text-muted-foreground text-xs tabular-nums">
                    {when(run.startedAt)}
                  </span>
                </p>
                {run.steps.length > 0 ? (
                  <ol className="text-muted-foreground flex flex-col gap-1 ps-4 text-xs">
                    {run.steps.map((step) => (
                      <li key={step.key} className="flex gap-2">
                        <span className="w-14 shrink-0">{step.status}</span>
                        <span className="truncate">{step.label}</span>
                      </li>
                    ))}
                  </ol>
                ) : null}
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}

export function AgentActivitySkeleton() {
  return <Skeleton className="h-96 w-full rounded-xl" />;
}
