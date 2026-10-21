"use client";

import { useAction } from "better-supabase/react";
import { PlusIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useState } from "react";
import { toast } from "sonner";

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
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { useErrorMessage } from "@/lib/use-error-message";

import type { ApprovalAction, SubjectOption } from "../approvals-types";

import { requestApproval } from "../approvals-actions";
import { APPROVAL_ACTIONS } from "../approvals-types";

function useActionLabel(): (action: string) => string {
  const t = useExtracted("approvals");

  return (action) => (action === "discount" ? t("Discount") : action);
}

/** Asks for an approval of an action on a customer, with a reason. */
export function RequestApprovalDialog({
  customers,
}: {
  customers: readonly SubjectOption[];
}) {
  const t = useExtracted("approvals");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const actionLabel = useActionLabel();
  const [open, setOpen] = useState(false);
  const [subjectId, setSubjectId] = useState<string | null>(null);
  const [action, setAction] = useState<ApprovalAction>("discount");
  const [reason, setReason] = useState("");

  const request = useAction(requestApproval, {
    onSuccess: () => {
      toast.success(t("Approval requested"));
      setSubjectId(null);
      setReason("");
      setOpen(false);
    },
  });

  const error =
    request.error === undefined ? null : errorMessage(request.error);

  const customerItems = customers.map((customer) => ({
    value: customer.id,
    label: customer.name,
  }));

  const actionItems = APPROVAL_ACTIONS.map((each) => ({
    value: each,
    label: actionLabel(each),
  }));

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);

        if (!next) {
          request.reset();
        }
      }}
    >
      <DialogTrigger render={<Button size="sm" />}>
        <PlusIcon />
        {t("Request approval")}
      </DialogTrigger>
      <DialogContent>
        <form
          className="grid gap-6"
          onSubmit={(event) => {
            event.preventDefault();

            if (subjectId !== null) {
              void request.run({ subjectId, action, reason });
            }
          }}
        >
          <DialogHeader>
            <DialogTitle>{t("Request approval")}</DialogTitle>
            <DialogDescription>
              {t("The approvers of the customer policy see it in their queue.")}
            </DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-customer`}>
                {t("Customer")}
              </FieldLabel>
              <Select
                value={subjectId}
                items={customerItems}
                onValueChange={(value) => {
                  setSubjectId(value);
                }}
              >
                <SelectTrigger id={`${fieldId}-customer`}>
                  <SelectValue placeholder={t("Pick a customer")} />
                </SelectTrigger>
                <SelectContent>
                  {customerItems.map((item) => (
                    <SelectItem key={item.value} value={item.value}>
                      {item.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-action`}>
                {t("Action")}
              </FieldLabel>
              <Select
                value={action}
                items={actionItems}
                onValueChange={(value) => {
                  const next = APPROVAL_ACTIONS.find((each) => each === value);

                  if (next) {
                    setAction(next);
                  }
                }}
              >
                <SelectTrigger id={`${fieldId}-action`}>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {actionItems.map((item) => (
                    <SelectItem key={item.value} value={item.value}>
                      {item.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
            <Field data-invalid={error ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-reason`}>
                {t("Reason")}
              </FieldLabel>
              <Textarea
                id={`${fieldId}-reason`}
                value={reason}
                required
                maxLength={500}
                onChange={(event) => {
                  setReason(event.target.value);
                }}
              />
              {error ? <FieldError>{error}</FieldError> : null}
            </Field>
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button
              type="submit"
              disabled={request.pending || subjectId === null}
            >
              {t("Send request")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
