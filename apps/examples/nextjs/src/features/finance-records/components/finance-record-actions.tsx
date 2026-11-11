"use client";

import { useAction, useActionForm } from "better-supabase/react";
import { PlusIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useState } from "react";

import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import {
  Field,
  FieldError,
  FieldGroup,
  FieldLabel,
} from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { issueInvoice } from "@/features/billing/billing-actions";
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

import {
  approvePayable,
  archiveLegalEntity,
  closePeriod,
  createBankAccount,
  createLegalEntity,
  createPayrollRun,
  decideExpenseReport,
  endFundingAward,
  fileTaxReturn,
  invoiceBillableTime,
  lockPeriod,
  makeDefaultLegalEntity,
  prepareTaxReturn,
  recordInvoicePayment,
  refreshPayrollRun,
  reimburseExpenseReport,
  reopenPeriod,
  submitExpenseReport,
  voidInvoice,
} from "../finance-records-actions";

type Action<I> = Parameters<typeof useAction<I, unknown>>[0];

/**
 * A button that runs one action with fixed input, toasts the outcome and leaves
 * the refresh to the action (it expires the tags the lists carry).
 */
function RunButton<I>({
  action,
  input,
  label,
  done,
  variant = "outline",
}: {
  action: Action<I>;
  input: Parameters<ReturnType<typeof useAction<I, unknown>>["run"]>[0];
  label: string;
  done: string;
  variant?: "outline" | "default" | "destructive";
}) {
  const errorMessage = useErrorMessage();

  const run = useAction(action, {
    onSuccess: () => {
      toast.success(done);
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <Button
      size="sm"
      variant={variant}
      disabled={run.pending}
      onClick={() => {
        void run.run(input);
      }}
    >
      {label}
    </Button>
  );
}

export interface FormField {
  readonly name: string;
  readonly label: string;
  readonly type?: "text" | "date";
  readonly placeholder?: string;
  readonly required?: boolean;
  readonly pattern?: string;
  readonly defaultValue?: string;
  readonly maxLength?: number;
}

/** A dialog with a form of text fields that submits one action. */
function FormDialog<T>({
  action,
  title,
  description,
  trigger,
  submit,
  done,
  fields,
  hidden = NO_HIDDEN,
  variant = "outline",
}: {
  action: Parameters<typeof useActionForm<T>>[0];
  title: string;
  description: string;
  trigger: string;
  submit: string;
  done: string;
  fields: readonly FormField[];
  /** Values the form sends without a field, such as the record's id. */
  hidden?: Readonly<Record<string, string>>;
  variant?: "outline" | "default";
}) {
  const t = useExtracted("finance");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);

  const form = useActionForm(action, {
    onSuccess: () => {
      toast.success(done);
      setOpen(false);
    },
  });

  const error = form.error === undefined ? null : errorMessage(form.error);

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);
        form.reset();
      }}
    >
      <DialogTrigger render={<Button size="sm" variant={variant} />}>
        <PlusIcon />
        {trigger}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <DialogHeader>
            <DialogTitle>{title}</DialogTitle>
            <DialogDescription>{description}</DialogDescription>
          </DialogHeader>
          {Object.entries(hidden).map(([name, value]) => (
            <input key={name} type="hidden" name={name} value={value} />
          ))}
          <FieldGroup>
            {fields.map((field, index) => (
              <Field
                key={field.name}
                data-invalid={error && index === 0 ? true : undefined}
              >
                <FieldLabel htmlFor={`${fieldId}-${field.name}`}>
                  {field.label}
                </FieldLabel>
                <Input
                  id={`${fieldId}-${field.name}`}
                  name={field.name}
                  type={field.type ?? "text"}
                  required={field.required ?? true}
                  maxLength={field.maxLength ?? 200}
                  autoComplete="off"
                  placeholder={field.placeholder}
                  pattern={field.pattern}
                  defaultValue={field.defaultValue}
                />
                {error && index === 0 ? <FieldError>{error}</FieldError> : null}
              </Field>
            ))}
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={form.pending}>
              {submit}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

const AMOUNT = String.raw`\d+(\.\d{1,2})?`;

const NO_HIDDEN: Readonly<Record<string, string>> = {};

/** What a person may do with an expense report in its status. */
export function ExpenseActions({
  reportId,
  status,
  canSubmit,
  canApprove,
  canManage,
}: {
  reportId: string;
  status: string;
  canSubmit: boolean;
  canApprove: boolean;
  canManage: boolean;
}) {
  const t = useExtracted("finance");

  return (
    <>
      {status === "draft" && canSubmit ? (
        <RunButton
          action={submitExpenseReport}
          input={{ reportId }}
          label={t("Submit for approval")}
          done={t("Report submitted")}
          variant="default"
        />
      ) : null}
      {status === "submitted" && canApprove ? (
        <>
          <RunButton
            action={decideExpenseReport}
            input={{ reportId, approved: true }}
            label={t("Approve")}
            done={t("Report approved")}
            variant="default"
          />
          <RunButton
            action={decideExpenseReport}
            input={{ reportId, approved: false }}
            label={t("Reject")}
            done={t("Report rejected")}
          />
        </>
      ) : null}
      {status === "approved" && canManage ? (
        <RunButton
          action={reimburseExpenseReport}
          input={{ reportId }}
          label={t("Reimburse")}
          done={t("Report reimbursed")}
          variant="default"
        />
      ) : null}
    </>
  );
}

/** Issue a draft, record a payment on an open invoice, or void it. */
export function InvoiceActions({
  invoiceId,
  status,
  currency,
  canWrite,
}: {
  invoiceId: string;
  status: string;
  currency: string;
  canWrite: boolean;
}) {
  const t = useExtracted("finance");

  if (!canWrite) {
    return null;
  }

  const open = status === "issued" || status === "partially_paid";

  return (
    <>
      {status === "draft" ? (
        <RunButton
          action={issueInvoice}
          input={{ invoiceId }}
          label={t("Issue")}
          done={t("Invoice issued")}
          variant="default"
        />
      ) : null}
      {open ? (
        <FormDialog
          action={recordInvoicePayment}
          title={t("Record a payment")}
          description={t("The payment is booked in the invoice's currency.")}
          trigger={t("Record payment")}
          submit={t("Record payment")}
          done={t("Payment recorded")}
          hidden={{ invoiceId, currency }}
          fields={[
            {
              name: "amount",
              label: t("Amount ({currency})", { currency }),
              placeholder: "190.00",
              pattern: AMOUNT,
              maxLength: 14,
            },
          ]}
        />
      ) : null}
      {status === "draft" || open ? (
        <RunButton
          action={voidInvoice}
          input={{ invoiceId }}
          label={t("Void")}
          done={t("Invoice voided")}
          variant="destructive"
        />
      ) : null}
    </>
  );
}

/** Approves a purchase bill at the caller's approval level. */
export function PayableActions({
  invoiceId,
  status,
  canApprove,
}: {
  invoiceId: string;
  status: string;
  canApprove: boolean;
}) {
  const t = useExtracted("finance");

  return canApprove && (status === "issued" || status === "partially_paid") ? (
    <RunButton
      action={approvePayable}
      input={{ invoiceId }}
      label={t("Approve for payment")}
      done={t("Bill approved")}
      variant="default"
    />
  ) : null;
}

/** Lock, close or reopen a period. */
export function PeriodActions({
  periodId,
  status,
}: {
  periodId: string;
  status: string;
}) {
  const t = useExtracted("finance");

  return status === "open" ? (
    <>
      <RunButton
        action={lockPeriod}
        input={{ periodId }}
        label={t("Lock")}
        done={t("Period locked")}
      />
      <RunButton
        action={closePeriod}
        input={{ periodId }}
        label={t("Close period")}
        done={t("Period closed")}
        variant="default"
      />
    </>
  ) : (
    <RunButton
      action={reopenPeriod}
      input={{ periodId }}
      label={t("Reopen")}
      done={t("Period reopened")}
    />
  );
}

/** Files a draft tax return. */
export function TaxReturnActions({
  returnId,
  status,
}: {
  returnId: string;
  status: string;
}) {
  const t = useExtracted("finance");

  return status === "draft" ? (
    <RunButton
      action={fileTaxReturn}
      input={{ returnId }}
      label={t("File return")}
      done={t("Return filed")}
      variant="default"
    />
  ) : null;
}

/** Prepares the return of a period. */
export function PrepareTaxReturnDialog() {
  const t = useExtracted("finance");

  return (
    <FormDialog
      action={prepareTaxReturn}
      title={t("Prepare a tax return")}
      description={t("The return adds up the posted tax of the period.")}
      trigger={t("Prepare return")}
      submit={t("Prepare return")}
      done={t("Return prepared")}
      fields={[
        { name: "since", label: t("From"), type: "date" },
        { name: "until", label: t("To"), type: "date" },
        {
          name: "period",
          label: t("Label"),
          placeholder: "2026-Q4",
          required: false,
          maxLength: 50,
        },
      ]}
    />
  );
}

/** Turns the unbilled time into a draft invoice. */
export function InvoiceTimeButton() {
  const t = useExtracted("finance");

  return (
    <RunButton
      action={invoiceBillableTime}
      input={{}}
      label={t("Invoice unbilled time")}
      done={t("Draft invoice created")}
    />
  );
}

/** Creates a draft payroll run for a period. */
export function CreatePayrollRunDialog() {
  const t = useExtracted("finance");

  return (
    <FormDialog
      action={createPayrollRun}
      title={t("New payroll run")}
      description={t("The run collects worked and leave hours of the period.")}
      trigger={t("New run")}
      submit={t("Create run")}
      done={t("Payroll run created")}
      fields={[
        { name: "from", label: t("From"), type: "date" },
        { name: "to", label: t("To"), type: "date" },
        { name: "label", label: t("Label"), required: false },
      ]}
    />
  );
}

/** Collects a draft run's lines again. */
export function RefreshPayrollRunButton({ runId }: { runId: string }) {
  const t = useExtracted("finance");

  return (
    <RunButton
      action={refreshPayrollRun}
      input={{ runId }}
      label={t("Collect again")}
      done={t("Run refreshed")}
    />
  );
}

/** Adds a legal entity. */
export function CreateLegalEntityDialog() {
  const t = useExtracted("finance");

  return (
    <FormDialog
      action={createLegalEntity}
      title={t("New legal entity")}
      description={t(
        "The first entity of an organization becomes its default.",
      )}
      trigger={t("New legal entity")}
      submit={t("Create entity")}
      done={t("Legal entity created")}
      fields={[
        {
          name: "code",
          label: t("Code"),
          placeholder: "ACME-NL",
          maxLength: 32,
        },
        { name: "name", label: t("Name") },
        {
          name: "vatNumber",
          label: t("VAT number"),
          required: false,
          maxLength: 50,
        },
        {
          name: "defaultCurrency",
          label: t("Currency"),
          placeholder: "EUR",
          required: false,
          pattern: "[A-Z]{3}",
          maxLength: 3,
        },
      ]}
    />
  );
}

/** Make default or archive a legal entity. */
export function LegalEntityActions({
  entityId,
  isDefault,
  archived,
}: {
  entityId: string;
  isDefault: boolean;
  archived: boolean;
}) {
  const t = useExtracted("finance");

  if (archived) {
    return null;
  }

  return (
    <>
      {isDefault ? null : (
        <RunButton
          action={makeDefaultLegalEntity}
          input={{ entityId }}
          label={t("Make default")}
          done={t("Default entity changed")}
        />
      )}
      {isDefault ? null : (
        <RunButton
          action={archiveLegalEntity}
          input={{ entityId }}
          label={t("Archive")}
          done={t("Legal entity archived")}
          variant="destructive"
        />
      )}
    </>
  );
}

/** Ends or cancels a funding award. */
export function FundingActions({
  awardId,
  status,
}: {
  awardId: string;
  status: string;
}) {
  const t = useExtracted("finance");

  return status === "active" ? (
    <>
      <RunButton
        action={endFundingAward}
        input={{ awardId }}
        label={t("End today")}
        done={t("Award ended")}
      />
      <RunButton
        action={endFundingAward}
        input={{ awardId, canceled: true }}
        label={t("Cancel award")}
        done={t("Award canceled")}
        variant="destructive"
      />
    </>
  ) : null;
}

/** Adds a bank account. */
export function CreateBankAccountDialog() {
  const t = useExtracted("finance");

  return (
    <FormDialog
      action={createBankAccount}
      title={t("New bank account")}
      description={t("Import a statement into it to start matching.")}
      trigger={t("New account")}
      submit={t("Create account")}
      done={t("Bank account created")}
      fields={[
        { name: "name", label: t("Name") },
        { name: "iban", label: t("IBAN"), required: false, maxLength: 34 },
        {
          name: "currency",
          label: t("Currency"),
          placeholder: "EUR",
          pattern: "[A-Z]{3}",
          maxLength: 3,
          defaultValue: "EUR",
        },
        { name: "holder", label: t("Holder"), required: false },
      ]}
    />
  );
}
