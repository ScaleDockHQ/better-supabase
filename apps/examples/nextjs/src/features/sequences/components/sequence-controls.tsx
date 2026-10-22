"use client";

import { useAction, useActionForm } from "better-supabase/react";
import { PauseIcon, PlayIcon, PlusIcon } from "lucide-react";
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
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { useErrorMessage } from "@/lib/use-error-message";

import {
  addSequenceStep,
  createSampleSequence,
  setSequenceStatus,
} from "../sequences-actions";

/** Saves a draft sequence with an email, a two-day wait and a task. */
export function SampleSequenceButton() {
  const t = useExtracted("sequences");
  const message = useErrorMessage();

  const create = useAction(createSampleSequence, {
    onSuccess: () => {
      toast.success(t("Sample sequence created"));
    },
    onError: (error) => {
      toast.error(message(error));
    },
  });

  return (
    <Button
      type="button"
      disabled={create.pending}
      onClick={() => {
        void create.run({
          name: t("Welcome series"),
          subject: t("Welcome to the team"),
          text: t("Reply to this email if you have questions."),
          task: t("Call the new customer"),
        });
      }}
    >
      <PlusIcon />
      {t("Create a sample sequence")}
    </Button>
  );
}

/** Activates a draft or paused sequence, or pauses an active one. */
export function SequenceStatusButton({
  sequenceId,
  active,
}: {
  sequenceId: string;
  active: boolean;
}) {
  const t = useExtracted("sequences");
  const message = useErrorMessage();

  const change = useAction(setSequenceStatus, {
    onSuccess: (data) => {
      toast.success(
        data.status === "active" ? t("Sequence active") : t("Sequence paused"),
      );
    },
    onError: (error) => {
      toast.error(message(error));
    },
  });

  return (
    <Button
      type="button"
      size="sm"
      variant="outline"
      disabled={change.pending}
      onClick={() => {
        void change.run({ sequenceId, status: active ? "paused" : "active" });
      }}
    >
      {active ? <PauseIcon /> : <PlayIcon />}
      {active ? t("Pause") : t("Activate")}
    </Button>
  );
}

type StepKind = "email" | "wait" | "task";

/** Appends an email, wait or task step to a sequence. */
export function AddStepDialog({ sequenceId }: { sequenceId: string }) {
  const t = useExtracted("sequences");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);
  const [kind, setKind] = useState<StepKind>("email");

  const form = useActionForm(addSequenceStep, {
    onSuccess: () => {
      setOpen(false);
      toast.success(t("Step added"));
    },
  });

  const error = form.error === undefined ? null : errorMessage(form.error);

  const kindItems: readonly { value: StepKind; label: string }[] = [
    { value: "email", label: t("Email") },
    { value: "wait", label: t("Wait") },
    { value: "task", label: t("Task") },
  ];

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger
        render={<Button type="button" size="sm" variant="outline" />}
      >
        <PlusIcon />
        {t("Add step")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <input type="hidden" name="sequenceId" value={sequenceId} />
          <DialogHeader>
            <DialogTitle>{t("Add a step")}</DialogTitle>
            <DialogDescription>
              {t(
                "Recipients already past the end run the new step on their next turn.",
              )}
            </DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-kind`}>{t("Kind")}</FieldLabel>
              <Select
                name="kind"
                value={kind}
                items={kindItems}
                onValueChange={(value) => {
                  if (
                    value === "email" ||
                    value === "wait" ||
                    value === "task"
                  ) {
                    setKind(value);
                  }
                }}
              >
                <SelectTrigger id={`${fieldId}-kind`} className="w-full">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {kindItems.map((item) => (
                    <SelectItem key={item.value} value={item.value}>
                      {item.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
            <Field data-invalid={error ? true : undefined}>
              <StepFields
                kind={kind}
                fieldId={fieldId}
                invalid={error !== null}
              />
              {error ? <FieldError>{error}</FieldError> : null}
            </Field>
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={form.pending}>
              {t("Add")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

function StepFields({
  kind,
  fieldId,
  invalid,
}: {
  kind: StepKind;
  fieldId: string;
  invalid: boolean;
}) {
  const t = useExtracted("sequences");
  const id = `${fieldId}-value`;
  const ariaInvalid = invalid ? true : undefined;

  switch (kind) {
    case "email": {
      return (
        <>
          <FieldLabel htmlFor={id}>{t("Subject")}</FieldLabel>
          <Input
            id={id}
            name="subject"
            placeholder={t("Following up")}
            required
            maxLength={200}
            aria-invalid={ariaInvalid}
          />
        </>
      );
    }

    case "wait": {
      return (
        <>
          <FieldLabel htmlFor={id}>{t("Minutes to wait")}</FieldLabel>
          <Input
            id={id}
            name="minutes"
            type="number"
            min={1}
            max={525_600}
            defaultValue={1440}
            required
            aria-invalid={ariaInvalid}
          />
        </>
      );
    }

    case "task": {
      return (
        <>
          <FieldLabel htmlFor={id}>{t("Task title")}</FieldLabel>
          <Input
            id={id}
            name="title"
            placeholder={t("Call the contact")}
            required
            maxLength={200}
            aria-invalid={ariaInvalid}
          />
        </>
      );
    }

    default: {
      const unknown: never = kind;

      return unknown;
    }
  }
}
