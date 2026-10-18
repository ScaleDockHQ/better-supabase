"use client";

import type { DbError } from "better-supabase";

import { useAction } from "better-supabase/react";
import { useExtracted } from "next-intl";
import { useId, useState } from "react";
import { toast } from "sonner";

import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
import { Button } from "@/components/ui/button";
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

import type { AccessRequestRow } from "../access-requests-queries";

import {
  cancelAccessRequest,
  decideAccessRequest,
  endAccess,
  requestAccess,
} from "../access-requests-actions";

type RequestRole = "member" | "admin";

type RequestDuration = "PT1H" | "P1D" | "P7D" | "none";

function isRole(value: unknown): value is RequestRole {
  return value === "member" || value === "admin";
}

function isDuration(value: unknown): value is RequestDuration {
  return (
    value === "PT1H" || value === "P1D" || value === "P7D" || value === "none"
  );
}

function useAccessErrorMessage(): (error: DbError) => string {
  const t = useExtracted("accessRequests");
  const errorMessage = useErrorMessage();

  return (error) =>
    error.kind === "conflict"
      ? t("You already have a pending request for this organization.")
      : errorMessage(error);
}

export function RequestAccessForm({ currentRole }: { currentRole: string }) {
  const t = useExtracted("accessRequests");
  const fieldId = useId();
  const errorMessage = useAccessErrorMessage();

  const [role, setRole] = useState<RequestRole>(
    currentRole === "admin" ? "member" : "admin",
  );

  const [duration, setDuration] = useState<RequestDuration>("P1D");
  const [reason, setReason] = useState("");

  const request = useAction(requestAccess, {
    onSuccess: () => {
      setReason("");
      toast.success(t("Request sent to the approvers"));
    },
  });

  const roleItems = [
    { value: "admin", label: t("Admin") },
    { value: "member", label: t("Member") },
  ];

  const durationItems = [
    { value: "PT1H", label: t("1 hour") },
    { value: "P1D", label: t("1 day") },
    { value: "P7D", label: t("7 days") },
    { value: "none", label: t("Until revoked") },
  ];

  const error =
    request.error === undefined ? null : errorMessage(request.error);

  return (
    <form
      className="flex flex-col gap-4"
      onSubmit={(event) => {
        event.preventDefault();
        void request.run({ role, duration, reason });
      }}
    >
      <FieldGroup>
        <div className="grid gap-4 sm:grid-cols-2">
          <Field>
            <FieldLabel htmlFor={`${fieldId}-role`}>{t("Role")}</FieldLabel>
            <Select
              value={role}
              items={roleItems}
              onValueChange={(value) => {
                if (isRole(value)) {
                  setRole(value);
                }
              }}
            >
              <SelectTrigger id={`${fieldId}-role`} className="w-full">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {roleItems.map((item) => (
                  <SelectItem key={item.value} value={item.value}>
                    {item.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </Field>
          <Field>
            <FieldLabel htmlFor={`${fieldId}-duration`}>
              {t("For how long")}
            </FieldLabel>
            <Select
              value={duration}
              items={durationItems}
              onValueChange={(value) => {
                if (isDuration(value)) {
                  setDuration(value);
                }
              }}
            >
              <SelectTrigger id={`${fieldId}-duration`} className="w-full">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {durationItems.map((item) => (
                  <SelectItem key={item.value} value={item.value}>
                    {item.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </Field>
        </div>
        <Field data-invalid={error ? true : undefined}>
          <FieldLabel htmlFor={`${fieldId}-reason`}>{t("Reason")}</FieldLabel>
          <Textarea
            id={`${fieldId}-reason`}
            value={reason}
            maxLength={500}
            placeholder={t("What do you need the role for?")}
            onChange={(event) => {
              setReason(event.target.value);
            }}
          />
          {error ? <FieldError>{error}</FieldError> : null}
        </Field>
      </FieldGroup>
      <div>
        <Button type="submit" disabled={request.pending}>
          {t("Request access")}
        </Button>
      </div>
    </form>
  );
}

function EndAccessButton({
  id,
  pending,
  onConfirm,
}: {
  id: string;
  pending: boolean;
  onConfirm: (id: string) => Promise<boolean>;
}) {
  const t = useExtracted("accessRequests");
  const [open, setOpen] = useState(false);

  return (
    <AlertDialog
      open={open}
      onOpenChange={(next) => {
        if (!pending) {
          setOpen(next);
        }
      }}
    >
      <AlertDialogTrigger
        render={<Button type="button" variant="outline" size="sm" />}
      >
        {t("End access")}
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>{t("End this access now?")}</AlertDialogTitle>
          <AlertDialogDescription>
            {t("The member goes back to the role they had before the request.")}
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel disabled={pending}>
            {t("Cancel")}
          </AlertDialogCancel>
          <AlertDialogAction
            type="button"
            variant="destructive"
            disabled={pending}
            onClick={() => {
              void onConfirm(id).then((done) => {
                if (done) {
                  setOpen(false);
                }
              });
            }}
          >
            {t("End access")}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}

export function AccessRequestActions({
  request,
  mine,
  canDecide,
}: {
  request: AccessRequestRow;
  mine: boolean;
  canDecide: boolean;
}) {
  const t = useExtracted("accessRequests");
  const errorMessage = useAccessErrorMessage();

  const onError = (error: DbError) => {
    toast.error(errorMessage(error));
  };

  const decide = useAction(decideAccessRequest, {
    onSuccess: () => {
      toast.success(t("Request decided"));
    },
    onError,
  });

  const cancel = useAction(cancelAccessRequest, {
    onSuccess: () => {
      toast.success(t("Request withdrawn"));
    },
    onError,
  });

  const end = useAction(endAccess, {
    onSuccess: () => {
      toast.success(t("Access ended"));
    },
    onError,
  });

  const { approvalId } = request;

  if (request.status === "pending" && approvalId !== null) {
    if (mine) {
      return (
        <Button
          type="button"
          variant="ghost"
          size="sm"
          disabled={cancel.pending}
          onClick={() => {
            void cancel.run({ approvalId });
          }}
        >
          {t("Withdraw")}
        </Button>
      );
    }

    if (canDecide) {
      return (
        <div className="flex justify-end gap-2">
          <Button
            type="button"
            variant="outline"
            size="sm"
            disabled={decide.pending}
            onClick={() => {
              void decide.run({ approvalId, decision: "reject" });
            }}
          >
            {t("Deny")}
          </Button>
          <Button
            type="button"
            size="sm"
            disabled={decide.pending}
            onClick={() => {
              void decide.run({ approvalId, decision: "approve" });
            }}
          >
            {t("Approve")}
          </Button>
        </div>
      );
    }
  }

  if (request.status === "granted" && (mine || canDecide)) {
    return (
      <EndAccessButton
        id={request.id}
        pending={end.pending}
        onConfirm={async (id) => (await end.run({ id })).ok}
      />
    );
  }

  return null;
}
