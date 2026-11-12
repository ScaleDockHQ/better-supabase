import { getExtracted } from "next-intl/server";
import { notFound } from "next/navigation";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { Badge } from "@/components/reui/badge";
import { CrmLoadError } from "@/features/crm/components/crm-load-error";
import { settle } from "@/features/crm/crm-queries";
import { Link, toAppHref } from "@/i18n/navigation";

import { loadMemberOptions } from "../member/member-queries";
import { loadContract, loadStatement } from "../revenue/revenue-queries";
import {
  addObligation,
  advanceStatement,
  setObligationStatus,
  transitionContract,
} from "../sales-actions";
import { ActionButton } from "./action-button";
import { ActionDialog } from "./action-dialog";
import { contractStatusLabels } from "./crm-overviews";
import { DetailTable, FactGrid } from "./detail-table";
import {
  dateFormatter,
  holds,
  moneyFormatter,
  requirePermission,
} from "./overview-support";

type Transition = "submit" | "return" | "activate" | "recall" | "terminate";

/** What a contract in each status may do next. */
const NEXT = new Map<string, readonly Transition[]>([
  ["draft", ["submit"]],
  ["in_review", ["activate", "return"]],
  ["out_for_signature", ["recall"]],
  ["active", ["terminate"]],
  ["expired", []],
  ["terminated", []],
]);

/** A contract with its dates, obligations and the next steps its status allows. */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function ContractDetail({ id }: { id: string }) {
  await requirePermission("contracts.read");

  const [t, loaded, fmtMoney, fmtDate, statusLabels, canWrite] =
    await Promise.all([
      getExtracted("sales"),
      settle(() => loadContract(id)),
      moneyFormatter(),
      dateFormatter(),
      contractStatusLabels(),
      holds("contracts.write"),
    ]);

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <CrmLoadError title={t("The contract didn't load")} />;
  }

  const contract = loaded.data;

  if (!contract) {
    notFound();
  }

  const labels: Readonly<Record<Transition, string>> = {
    submit: t("Submit for review"),
    return: t("Return to draft"),
    activate: t("Activate"),
    recall: t("Recall"),
    terminate: t("Terminate"),
  };

  const obligationLabels = new Map<string, string>([
    ["open", t("Open")],
    ["done", t("Done")],
    ["waived", t("Waived")],
  ]);

  const next = NEXT.get(contract.status) ?? [];

  return (
    <RecordDetailFrame
      title={contract.title}
      description={contract.description ?? undefined}
      status={
        <Badge
          variant={contract.status === "active" ? "success-light" : "secondary"}
        >
          {statusLabels[contract.status] ?? contract.status}
        </Badge>
      }
      actions={
        canWrite
          ? next.map((action) => (
              <ActionButton
                key={action}
                action={transitionContract}
                input={{ contractId: contract.id, action }}
                label={labels[action]}
                successMessage={t("Contract updated")}
                variant={action === "terminate" ? "destructive" : "outline"}
              />
            ))
          : undefined
      }
    >
      <FactGrid
        facts={[
          {
            label: t("Value"),
            value: contract.value ? fmtMoney(contract.value) : "–",
          },
          { label: t("Starts"), value: fmtDate(contract.startsOn) },
          { label: t("Ends"), value: fmtDate(contract.endsOn) },
          { label: t("Notice by"), value: fmtDate(contract.noticeDeadline) },
          {
            label: t("Renewal"),
            value: contract.autoRenew
              ? t("Every {months} months", {
                  months: String(contract.renewalMonths),
                })
              : t("Manual"),
          },
          { label: t("Renewed"), value: String(contract.renewedCount) },
        ]}
      />
      <DetailTable
        title={t("Obligations")}
        description={t("What each party has to do, and by when.")}
        head={[t("Obligation"), t("Due"), t("Status"), ""]}
        rows={contract.obligations.map((obligation) => ({
          key: obligation.id,
          cells: [
            obligation.title,
            <span
              key="d"
              className={obligation.overdue ? "text-destructive" : undefined}
            >
              {fmtDate(obligation.dueOn)}
            </span>,
            <Badge
              key="s"
              variant={
                obligation.status === "done"
                  ? "success-light"
                  : obligation.overdue
                    ? "destructive-light"
                    : "secondary"
              }
            >
              {obligationLabels.get(obligation.status) ?? obligation.status}
            </Badge>,
            canWrite && obligation.status === "open" ? (
              <ActionButton
                key="a"
                action={setObligationStatus}
                input={{ obligationId: obligation.id, status: "done" }}
                label={t("Mark done")}
                successMessage={t("Obligation updated")}
              />
            ) : null,
          ],
        }))}
        emptyTitle={t("No obligations yet")}
        action={
          canWrite ? (
            <ActionDialog
              action={addObligation}
              title={t("Add obligation")}
              trigger={t("Add obligation")}
              submitLabel={t("Add")}
              successMessage={t("Obligation added")}
              variant="outline"
              hidden={{ contractId: contract.id }}
              fields={[
                {
                  name: "title",
                  label: t("Title"),
                  kind: "text",
                  required: true,
                },
                { name: "dueOn", label: t("Due"), kind: "date" },
              ]}
            />
          ) : undefined
        }
      />
    </RecordDetailFrame>
  );
}

/** A commission statement with its lines, finalized and then paid. */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function StatementDetail({ id }: { id: string }) {
  await requirePermission("commissions.read");

  const [t, loaded, fmtMoney, fmtDate, members, canManage] = await Promise.all([
    getExtracted("sales"),
    settle(() => loadStatement(id)),
    moneyFormatter(),
    dateFormatter(),
    loadMemberOptions(),
    holds("commissions.manage"),
  ]);

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <CrmLoadError title={t("The statement didn't load")} />;
  }

  const statement = loaded.data;

  if (!statement) {
    notFound();
  }

  const seller =
    members.find((member) => member.userId === statement.sellerId)?.name ??
    statement.sellerId;

  const step =
    statement.status === "open"
      ? "finalize"
      : statement.status === "finalized"
        ? "pay"
        : null;

  return (
    <RecordDetailFrame
      title={seller}
      description={`${fmtDate(statement.startsOn)} – ${fmtDate(statement.endsOn)}`}
      status={
        <Badge
          variant={statement.status === "paid" ? "success-light" : "secondary"}
        >
          {statement.status}
        </Badge>
      }
      actions={
        canManage && step ? (
          <ActionButton
            action={advanceStatement}
            input={{ statementId: statement.id, step }}
            label={step === "finalize" ? t("Finalize") : t("Pay out")}
            successMessage={
              step === "finalize"
                ? t("Statement finalized")
                : t("Statement paid")
            }
            variant="default"
          />
        ) : undefined
      }
    >
      <FactGrid
        facts={[
          { label: t("Total"), value: fmtMoney(statement.total) },
          { label: t("Lines"), value: String(statement.lines.length) },
          { label: t("Paid"), value: fmtDate(statement.paidAt) },
        ]}
      />
      <DetailTable
        title={t("Commissions")}
        head={[t("Source"), t("Date"), t("Sale"), t("Commission")]}
        rows={statement.lines.map((line) => ({
          key: line.id,
          cells: [
            line.sourceType === "deal" ? (
              <Link
                key="l"
                href={toAppHref(`/crm/deals/${line.sourceId}`)}
                className="font-medium hover:underline"
              >
                {line.sourceType}
              </Link>
            ) : (
              line.sourceType
            ),
            fmtDate(line.occurredOn),
            fmtMoney(line.basis),
            fmtMoney(line.amount),
          ],
        }))}
        emptyTitle={t("No commissions in this statement")}
      />
    </RecordDetailFrame>
  );
}
