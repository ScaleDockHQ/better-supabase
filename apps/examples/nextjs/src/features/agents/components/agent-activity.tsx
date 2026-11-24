import { getExtracted } from "next-intl/server";

import { KpiBand } from "@/components/record-list/kpi-band";
import { Badge } from "@/components/reui/badge";
import {
  Card,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Link } from "@/i18n/navigation";

import type { AgentActivity } from "../agent-activity-queries";

import { AgentApprovalButtons } from "./agent-approval-buttons";

const dateTime = new Intl.DateTimeFormat("en", {
  dateStyle: "medium",
  timeStyle: "short",
});

/** The agent's counts, as the KPI band of every tab. */
export async function AgentKpis({ activity }: { activity: AgentActivity }) {
  const t = await getExtracted("agents");
  const failed = activity.runs.filter((run) => run.status === "failed").length;

  const blocked = activity.decisions.filter(
    (row) => row.decision === "block",
  ).length;

  return (
    <KpiBand
      kpis={[
        { label: t("Runs"), value: String(activity.runs.length) },
        { label: t("Failed runs"), value: String(failed) },
        {
          label: t("Pending approvals"),
          value: String(activity.approvals.length),
        },
        { label: t("Guardrail blocks"), value: String(blocked) },
      ]}
    />
  );
}

function EmptyCard({ title, hint }: { title: string; hint: string }) {
  return (
    <Card size="sm">
      <CardHeader>
        <CardTitle>{title}</CardTitle>
        <CardDescription>{hint}</CardDescription>
      </CardHeader>
    </Card>
  );
}

export async function AgentRuns({ activity }: { activity: AgentActivity }) {
  const t = await getExtracted("agents");

  if (activity.runs.length === 0) {
    return (
      <EmptyCard
        title={t("No runs yet")}
        hint={t("Runs of chats that use this agent show up here.")}
      />
    );
  }

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>{t("Run")}</TableHead>
          <TableHead>{t("Status")}</TableHead>
          <TableHead>{t("Model")}</TableHead>
          <TableHead>{t("Started")}</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {activity.runs.map((run) => (
          <TableRow key={run.id}>
            <TableCell>
              <Link
                href={`/assistant/agents/runs/${run.id}`}
                className="font-medium hover:underline"
              >
                {run.id.slice(0, 8)}
              </Link>
            </TableCell>
            <TableCell>
              <Badge
                variant={
                  run.status === "completed"
                    ? "success-light"
                    : run.status === "failed"
                      ? "destructive-light"
                      : "secondary"
                }
              >
                {run.status}
              </Badge>
            </TableCell>
            <TableCell className="text-muted-foreground">
              {run.model ?? "–"}
            </TableCell>
            <TableCell className="text-muted-foreground tabular-nums">
              {dateTime.format(new Date(run.startedAt))}
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}

export async function AgentApprovals({
  activity,
  canDecide,
}: {
  activity: AgentActivity;
  canDecide: boolean;
}) {
  const t = await getExtracted("agents");

  if (activity.approvals.length === 0) {
    return (
      <EmptyCard
        title={t("Nothing to approve")}
        hint={t("Tool calls of this agent that need a decision show up here.")}
      />
    );
  }

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>{t("Tool")}</TableHead>
          <TableHead>{t("Input")}</TableHead>
          <TableHead>{t("Chat")}</TableHead>
          <TableHead />
        </TableRow>
      </TableHeader>
      <TableBody>
        {activity.approvals.map((approval) => (
          <TableRow key={approval.approvalId}>
            <TableCell className="font-medium">{approval.tool}</TableCell>
            <TableCell className="max-w-xs truncate font-mono text-xs text-muted-foreground">
              {approval.input}
            </TableCell>
            <TableCell>
              <Link
                href={`/assistant/${approval.chatId}`}
                className="hover:underline"
              >
                {approval.chatTitle === ""
                  ? approval.chatId.slice(0, 8)
                  : approval.chatTitle}
              </Link>
            </TableCell>
            <TableCell className="text-right">
              {canDecide ? (
                <AgentApprovalButtons approvalId={approval.approvalId} />
              ) : null}
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}

export async function AgentGuardrails({
  activity,
}: {
  activity: AgentActivity;
}) {
  const t = await getExtracted("agents");

  if (activity.decisions.length === 0) {
    return (
      <EmptyCard
        title={t("No guardrail hits")}
        hint={t("Decisions of the guardrails for this agent show up here.")}
      />
    );
  }

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>{t("Stage")}</TableHead>
          <TableHead>{t("Decision")}</TableHead>
          <TableHead>{t("Reasons")}</TableHead>
          <TableHead>{t("When")}</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {activity.decisions.map((row) => (
          <TableRow key={row.id}>
            <TableCell>{row.stage}</TableCell>
            <TableCell>
              <Badge
                variant={
                  row.decision === "block" ? "destructive-light" : "secondary"
                }
              >
                {row.decision}
              </Badge>
            </TableCell>
            <TableCell className="text-muted-foreground">
              {row.reasons === "" ? "–" : row.reasons}
            </TableCell>
            <TableCell className="text-muted-foreground tabular-nums">
              {dateTime.format(new Date(row.createdAt))}
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}
