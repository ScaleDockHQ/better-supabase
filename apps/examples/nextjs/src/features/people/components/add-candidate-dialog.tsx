"use client";

import { useActionForm } from "better-supabase/react";
import { UserPlusIcon } from "lucide-react";
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
  FieldDescription,
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
import { useErrorMessage } from "@/lib/use-error-message";

import type { CandidateOption } from "../people-queries";

import { addCandidate } from "../people-actions";

/** Adds a record the app registers as a subject (a customer) as a candidate. */
export function AddCandidateDialog({
  jobId,
  candidates,
}: {
  jobId: string;
  candidates: readonly CandidateOption[];
}) {
  const t = useExtracted("people");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);

  const form = useActionForm(addCandidate, {
    onSuccess: () => {
      setOpen(false);
      toast.success(t("Candidate added"));
    },
  });

  const error = form.error === undefined ? null : errorMessage(form.error);

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger render={<Button variant="outline" />}>
        <UserPlusIcon />
        {t("Add candidate")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <input type="hidden" name="jobId" value={jobId} />
          <DialogHeader>
            <DialogTitle>{t("Add candidate")}</DialogTitle>
            <DialogDescription>
              {t("They start in the first stage of this opening.")}
            </DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field data-invalid={error ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-candidate`}>
                {t("Candidate")}
              </FieldLabel>
              <Select name="candidateId" items={[...candidates]} required>
                <SelectTrigger id={`${fieldId}-candidate`} className="w-full">
                  <SelectValue placeholder={t("Pick a record")} />
                </SelectTrigger>
                <SelectContent>
                  {candidates.map((candidate) => (
                    <SelectItem key={candidate.value} value={candidate.value}>
                      {candidate.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <FieldDescription>
                {t("Candidates are customer records for now.")}
              </FieldDescription>
              {error ? <FieldError>{error}</FieldError> : null}
            </Field>
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button
              type="submit"
              disabled={form.pending || candidates.length === 0}
            >
              {t("Add")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
