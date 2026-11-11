import type { ReactNode } from "react";

import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import type { FinanceEntityKey } from "@/lib/finance-list";

import { PageHeader } from "@/components/page-header";
import { buttonVariants } from "@/components/ui/button";
import {
  FinanceDetail,
  FinanceDetailSkeleton,
} from "@/features/finance-records/components/finance-detail";
import {
  FinanceList,
  FinanceListSkeleton,
} from "@/features/finance-records/components/finance-list";
import {
  CreateBankAccountDialog,
  CreateLegalEntityDialog,
  CreatePayrollRunDialog,
  InvoiceTimeButton,
  PrepareTaxReturnDialog,
} from "@/features/finance-records/components/finance-record-actions";
import { FINANCE_PATHS } from "@/features/finance-records/finance-records-paths";
import { ConnectivityFallback } from "@/features/offline/components/connectivity-fallback";
import { PermissionGate } from "@/features/user/components/permission-gate";
import type { Permission } from "@/features/user/user-permissions";
import { Link } from "@/i18n/navigation";

/** The permission that reads each entity, and the one that writes it. */
const READ: Readonly<Record<FinanceEntityKey, Permission>> = {
  invoices: "invoices.read",
  payables: "invoices.read",
  expenses: "expenses.read",
  ledger: "ledger.read",
  journal: "accounting.read",
  "billable-time": "billable_time.read",
  recurring: "accounting.read",
  tax: "tax.read",
  periods: "periods.read",
  payroll: "payroll_export.read",
  "legal-entities": "legal_entities.read",
  funding: "funding.read",
  "bank-accounts": "banking.read",
  "bank-transactions": "banking.read",
};

/** The create action of an entity's overview, with the permission it needs. */
function createFor(
  entity: FinanceEntityKey,
): { readonly permission: Permission; readonly node: ReactNode } | null {
  switch (entity) {
    case "tax": {
      return { permission: "tax.manage", node: <PrepareTaxReturnDialog /> };
    }
    case "billable-time": {
      return { permission: "billable_time.invoice", node: <InvoiceTimeButton /> };
    }
    case "payroll": {
      return {
        permission: "payroll_export.export",
        node: <CreatePayrollRunDialog />,
      };
    }
    case "legal-entities": {
      return {
        permission: "legal_entities.manage",
        node: <CreateLegalEntityDialog />,
      };
    }
    case "bank-accounts": {
      return { permission: "banking.manage", node: <CreateBankAccountDialog /> };
    }
    case "invoices":
    case "payables":
    case "expenses":
    case "ledger":
    case "journal":
    case "recurring":
    case "periods":
    case "funding":
    case "bank-transactions": {
      return null;
    }
    default: {
      const unknown: never = entity;

      return unknown;
    }
  }
}

function useOverviewCopy(entity: FinanceEntityKey): {
  readonly title: string;
  readonly description: string;
} {
  const t = useExtracted("finance");

  switch (entity) {
    case "invoices": {
      return {
        title: t("Invoices"),
        description: t(
          "Every sales and purchase invoice, with its status, due date and what is still owed.",
        ),
      };
    }
    case "payables": {
      return {
        title: t("Bills"),
        description: t("Purchase invoices to approve and pay."),
      };
    }
    case "expenses": {
      return {
        title: t("Expenses"),
        description: t(
          "Expense reports from submission to reimbursement, with their receipts.",
        ),
      };
    }
    case "ledger": {
      return {
        title: t("Ledger"),
        description: t(
          "The append-only transactions the blocks post, each with its entries.",
        ),
      };
    }
    case "journal": {
      return {
        title: t("Journal"),
        description: t(
          "Double-entry journal entries of the books, with their lines per account.",
        ),
      };
    }
    case "billable-time": {
      return {
        title: t("Billable time"),
        description: t(
          "Logged time with its rate, and what is already on an invoice.",
        ),
      };
    }
    case "recurring": {
      return {
        title: t("Recurring postings"),
        description: t(
          "Schedules that spread an amount over periods, such as deferred revenue.",
        ),
      };
    }
    case "tax": {
      return {
        title: t("Tax returns"),
        description: t("Returns prepared from posted tax, per period."),
      };
    }
    case "periods": {
      return {
        title: t("Periods"),
        description: t("Fiscal periods that lock and close the books."),
      };
    }
    case "payroll": {
      return {
        title: t("Payroll runs"),
        description: t("Runs collected from worked and leave hours."),
      };
    }
    case "legal-entities": {
      return {
        title: t("Legal entities"),
        description: t("Companies inside this organization."),
      };
    }
    case "funding": {
      return {
        title: t("Awards"),
        description: t("Units funders award, with the share each award used."),
      };
    }
    case "bank-accounts": {
      return {
        title: t("Bank accounts"),
        description: t("Accounts statements are imported into."),
      };
    }
    case "bank-transactions": {
      return {
        title: t("Bank transactions"),
        description: t("Every imported transaction, matched or not."),
      };
    }
    default: {
      const unknown: never = entity;

      return unknown;
    }
  }
}

function useBackLabel(entity: FinanceEntityKey): string {
  const t = useExtracted("finance");

  switch (entity) {
    case "invoices": {
      return t("All invoices");
    }
    case "payables": {
      return t("All bills");
    }
    case "expenses": {
      return t("All expense reports");
    }
    case "ledger": {
      return t("All ledger transactions");
    }
    case "journal": {
      return t("All journal entries");
    }
    case "billable-time": {
      return t("All time entries");
    }
    case "recurring": {
      return t("All schedules");
    }
    case "tax": {
      return t("All tax returns");
    }
    case "periods": {
      return t("All periods");
    }
    case "payroll": {
      return t("All payroll runs");
    }
    case "legal-entities": {
      return t("All legal entities");
    }
    case "funding": {
      return t("All awards");
    }
    case "bank-accounts": {
      return t("All bank accounts");
    }
    case "bank-transactions": {
      return t("All bank transactions");
    }
    default: {
      const unknown: never = entity;

      return unknown;
    }
  }
}

/**
 * The page of one finance overview: the header with the entity's create action
 * and the list on the list kit. A route's page renders this and exports
 * `ensureStatic` and `instant`.
 */
export function FinanceOverviewPage({
  entity,
  embedded = false,
}: {
  entity: FinanceEntityKey;
  /** A section under the header of a page that has its own, not a page. */
  embedded?: boolean;
}) {
  const { title, description } = useOverviewCopy(entity);
  const create = createFor(entity);

  const actions = create ? (
    <Suspense fallback={null}>
      <PermissionGate permission={create.permission}>{create.node}</PermissionGate>
    </Suspense>
  ) : null;

  return (
    <>
      {embedded ? (
        <div className="flex flex-wrap items-end justify-between gap-4">
          <div className="space-y-1">
            <h2 className="text-lg font-semibold tracking-tight">{title}</h2>
            <p className="text-sm text-muted-foreground">{description}</p>
          </div>
          {actions ? <div className="flex items-center gap-2">{actions}</div> : null}
        </div>
      ) : (
        <PageHeader title={title} description={description} actions={actions} />
      )}
      <Suspense
        fallback={
          <ConnectivityFallback>
            <FinanceListSkeleton />
          </ConnectivityFallback>
        }
      >
        <PermissionGate permission={READ[entity]}>
          <FinanceList entity={entity} create={create?.node} />
        </PermissionGate>
      </Suspense>
    </>
  );
}

/**
 * The page of one finance record: a back link, then the record behind the
 * page's boundary. `ids` is the page's `params.then(({ id }) => id)`.
 */
export function FinanceDetailPage({
  entity,
  ids,
}: {
  entity: FinanceEntityKey;
  ids: Promise<string>;
}) {
  const back = useBackLabel(entity);

  return (
    <>
      <Link
        href={FINANCE_PATHS[entity]}
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {back}
      </Link>
      <Suspense
        fallback={
          <ConnectivityFallback>
            <FinanceDetailSkeleton />
          </ConnectivityFallback>
        }
      >
        {ids.then((id) => (
          <PermissionGate permission={READ[entity]}>
            <FinanceDetail entity={entity} id={id} />
          </PermissionGate>
        ))}
      </Suspense>
    </>
  );
}
