"use client";

import { useActionForm } from "better-supabase/react";
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
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { useErrorMessage } from "@/lib/use-error-message";

import type { TeamOption } from "../work-types";

import { usePriorityLabel } from "../use-work-labels";
import { createWorkItem } from "../work-actions";

const NO_TEAM = "";

/** A dialog that creates a work item with a title, a team and a priority. */
export function CreateWorkItemDialog({
  teams,
  defaultTeamId,
}: {
  teams: readonly TeamOption[];
  defaultTeamId: string | null;
}) {
  const t = useExtracted("work");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const priorityLabel = usePriorityLabel();
  const [open, setOpen] = useState(false);
  const [teamId, setTeamId] = useState(defaultTeamId ?? NO_TEAM);
  const [priority, setPriority] = useState("0");

  const form = useActionForm(createWorkItem, {
    onSuccess: (identifier) => {
      toast.success(t("Created {identifier}", { identifier }));
      setOpen(false);
    },
  });

  const error = form.error === undefined ? null : errorMessage(form.error);

  const teamItems = [
    { value: NO_TEAM, label: t("No team") },
    ...teams.map((team) => ({ value: team.id, label: team.name })),
  ];

  const priorityItems = ["0", "1", "2", "3", "4"].map((value) => ({
    value,
    label: priorityLabel(Number(value)),
  }));

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);

        if (!next) {
          form.reset();
        }
      }}
    >
      <DialogTrigger render={<Button size="sm" />}>
        <PlusIcon />
        {t("New item")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <DialogHeader>
            <DialogTitle>{t("New work item")}</DialogTitle>
            <DialogDescription>
              {t("It starts in the first stage of your workflow.")}
            </DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field data-invalid={error ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-title`}>{t("Title")}</FieldLabel>
              <Input
                id={`${fieldId}-title`}
                name="title"
                required
                maxLength={200}
                autoComplete="off"
              />
              {error ? <FieldError>{error}</FieldError> : null}
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-team`}>{t("Team")}</FieldLabel>
              <input type="hidden" name="teamId" value={teamId} />
              <Select
                value={teamId}
                items={teamItems}
                onValueChange={(value) => {
                  setTeamId(value ?? NO_TEAM);
                }}
              >
                <SelectTrigger id={`${fieldId}-team`}>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {teamItems.map((item) => (
                    <SelectItem key={item.value} value={item.value}>
                      {item.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-priority`}>
                {t("Priority")}
              </FieldLabel>
              <input type="hidden" name="priority" value={priority} />
              <Select
                value={priority}
                items={priorityItems}
                onValueChange={(value) => {
                  setPriority(value ?? "0");
                }}
              >
                <SelectTrigger id={`${fieldId}-priority`}>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {priorityItems.map((item) => (
                    <SelectItem key={item.value} value={item.value}>
                      {item.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={form.pending}>
              {t("Create item")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
