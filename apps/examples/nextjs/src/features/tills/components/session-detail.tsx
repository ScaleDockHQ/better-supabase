import { getExtracted } from "next-intl/server";
import { notFound } from "next/navigation";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { RecordDetailTabs } from "@/components/record-detail/record-detail-tabs";
import { Badge } from "@/components/reui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { CrmLoadError } from "@/features/crm/components/crm-load-error";
import { settle } from "@/features/crm/crm-queries";
import { ActionDialog } from "@/features/sales/components/action-dialog";
import {
  DetailTable,
  FactGrid,
} from "@/features/sales/components/detail-table";
import {
  dateFormatter,
  holds,
  moneyFormatter,
  requirePermission,
} from "@/features/sales/components/overview-support";

import {
  closeSession,
  depositCash,
  importDepositStatement,
  reconcileDeposit,
  recordMovement,
} from "../tills-actions";
import { loadBankTargets, loadSession } from "../tills-queries";

export function SessionDetailSkeleton() {
  return <Skeleton className="h-96 rounded-xl" aria-busy="true" />;
}

/** A shift with its cash movements, the closing count and the deposits. */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function SessionDetail({ id, tab }: { id: string; tab: string }) {
  await requirePermission("tills.read");

  const [t, loaded, fmtDate, fmtMoney, canWrite, canManage, canImport, bank] =
    await Promise.all([
      getExtracted("tills"),
      settle(() => loadSession(id)),
      dateFormatter(),
      moneyFormatter(),
      holds("tills.write"),
      holds("tills.manage"),
      holds("banking.import"),
      tab === "deposits" ? settle(loadBankTargets) : undefined,
    ]);

  const targets = bank?.kind === "ok" ? bank.data : undefined;

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <CrmLoadError title={t("The session didn't load")} />;
  }

  const shift = loaded.data;

  if (!shift) {
    notFound();
  }

  const open = shift.status === "open";
  const currency = shift.expected.currency;

  const kinds = new Map([
    ["cash_sale", t("Cash sale")],
    ["cash_refund", t("Cash refund")],
    ["cash_in", t("Cash in")],
    ["cash_out", t("Cash out")],
  ]);

  return (
    <RecordDetailFrame
      title={shift.till}
      description={t("Opened {date}", { date: fmtDate(shift.openedAt) })}
      status={
        <Badge variant={open ? "info-light" : "secondary"}>
          {open ? t("Open") : t("Closed")}
        </Badge>
      }
      actions={
        canWrite || canManage ? (
          open && canWrite ? (
            <>
              <ActionDialog
                action={recordMovement}
                title={t("Record cash movement")}
                trigger={t("Record movement")}
                submitLabel={t("Record")}
                successMessage={t("Movement recorded")}
                variant="outline"
                hidden={{ sessionId: shift.id, currency }}
                fields={[
                  {
                    name: "kind",
                    label: t("Kind"),
                    kind: "select",
                    options: [...kinds].map(([value, label]) => ({
                      value,
                      label,
                    })),
                  },
                  {
                    name: "amount",
                    label: t("Amount ({currency})", { currency }),
                    kind: "decimal",
                    required: true,
                  },
                  { name: "reason", label: t("Reason"), kind: "text" },
                ]}
              />
              <ActionDialog
                action={closeSession}
                title={t("Count the drawer and close")}
                description={t(
                  "Expected cash is {expected}. A difference is booked to accounting.",
                  { expected: fmtMoney(shift.expected) },
                )}
                trigger={t("Close session")}
                submitLabel={t("Close session")}
                successMessage={t("Session closed")}
                hidden={{ sessionId: shift.id, currency }}
                fields={[
                  {
                    name: "counted",
                    label: t("Counted ({currency})", { currency }),
                    kind: "decimal",
                    required: true,
                  },
                  { name: "notes", label: t("Notes"), kind: "text" },
                ]}
              />
            </>
          ) : !open && canManage ? (
            <ActionDialog
              action={depositCash}
              title={t("Deposit cash")}
              trigger={t("Deposit cash")}
              submitLabel={t("Deposit")}
              successMessage={t("Deposit recorded")}
              hidden={{ sessionId: shift.id, currency }}
              fields={[
                {
                  name: "amount",
                  label: t("Amount ({currency})", { currency }),
                  kind: "decimal",
                  required: true,
                },
                { name: "reference", label: t("Reference"), kind: "text" },
              ]}
            />
          ) : undefined
        ) : undefined
      }
    >
      <RecordDetailTabs
        base={`/tills/${id}`}
        active={tab}
        tabs={[
          { value: "movements", label: t("Movements") },
          { value: "count", label: t("Cash count") },
          { value: "deposits", label: t("Deposits") },
        ]}
      />
      {tab === "count" ? (
        shift.count ? (
          <FactGrid
            facts={[
              { label: t("Expected"), value: fmtMoney(shift.count.expected) },
              { label: t("Counted"), value: fmtMoney(shift.count.counted) },
              { label: t("Variance"), value: fmtMoney(shift.count.variance) },
              { label: t("Counted on"), value: fmtDate(shift.count.countedAt) },
              { label: t("Notes"), value: shift.count.notes ?? "–" },
            ]}
          />
        ) : (
          <DetailTable
            title={t("Cash count")}
            head={[t("Expected"), t("Counted")]}
            rows={[]}
            emptyTitle={t("Not counted yet")}
            emptyDescription={t(
              "Close the session to count the drawer. The count is booked to accounting.",
            )}
          />
        )
      ) : tab === "deposits" ? (
        <DetailTable
          title={t("Deposits")}
          description={t(
            "Cash taken to the bank. A deposit is reconciled when it matches a bank transaction.",
          )}
          action={
            canImport && targets && targets.accounts.length > 0 ? (
              <ActionDialog
                action={importDepositStatement}
                title={t("Import bank statement")}
                description={t(
                  "Paste an MT940 statement. A transaction that was imported before is skipped.",
                )}
                trigger={t("Import statement")}
                submitLabel={t("Import")}
                successMessage={t("Statement imported")}
                variant="outline"
                fields={[
                  {
                    name: "accountId",
                    label: t("Bank account"),
                    kind: "select",
                    required: true,
                    options: targets.accounts.map((account) => ({
                      value: account.id,
                      label: account.name,
                    })),
                  },
                  {
                    name: "statement",
                    label: t("MT940 statement"),
                    kind: "textarea",
                    required: true,
                  },
                ]}
              />
            ) : undefined
          }
          head={[
            t("Amount"),
            t("Date"),
            t("Reference"),
            t("Status"),
            t("Bank transaction"),
          ]}
          rows={shift.deposits.map((deposit) => ({
            key: deposit.id,
            cells: [
              fmtMoney(deposit.amount),
              fmtDate(deposit.depositedOn),
              deposit.reference ?? "–",
              <Badge
                key="status"
                variant={
                  deposit.status === "reconciled"
                    ? "success-light"
                    : "warning-light"
                }
              >
                {deposit.status === "reconciled"
                  ? t("Reconciled")
                  : t("Pending")}
              </Badge>,
              canManage && deposit.status === "pending" && targets ? (
                <ActionDialog
                  key="match"
                  action={reconcileDeposit}
                  title={t("Match to a bank transaction")}
                  description={t(
                    "Only unmatched transactions for the same amount are offered. Import a statement first when the list is empty.",
                  )}
                  trigger={t("Match")}
                  submitLabel={t("Match deposit")}
                  successMessage={t("Deposit matched")}
                  variant="outline"
                  hidden={{ depositId: deposit.id }}
                  fields={[
                    {
                      name: "bankTransactionId",
                      label: t("Bank transaction"),
                      kind: "select",
                      required: true,
                      options: targets.transactions
                        .filter(
                          (row) =>
                            row.amount.amount === deposit.amount.amount &&
                            row.amount.currency === deposit.amount.currency,
                        )
                        .map((row) => ({ value: row.id, label: row.label })),
                    },
                  ]}
                />
              ) : (
                "–"
              ),
            ],
          }))}
          emptyTitle={t("No deposits")}
          emptyDescription={t("Deposit the cash of a closed session.")}
        />
      ) : (
        <>
          <FactGrid
            facts={[
              {
                label: t("Opening float"),
                value: fmtMoney(shift.openingFloat),
              },
              { label: t("Expected cash"), value: fmtMoney(shift.expected) },
              { label: t("Movements"), value: String(shift.movements.length) },
            ]}
          />
          <DetailTable
            title={t("Movements")}
            head={[t("Kind"), t("Amount"), t("Reason"), t("When")]}
            rows={shift.movements.map((movement) => ({
              key: movement.id,
              cells: [
                kinds.get(movement.kind) ?? movement.kind,
                fmtMoney(movement.amount),
                movement.reason ?? "–",
                fmtDate(movement.createdAt),
              ],
            }))}
            emptyTitle={t("No movements")}
            emptyDescription={t("Cash sales and drawer movements show here.")}
          />
        </>
      )}
    </RecordDetailFrame>
  );
}
