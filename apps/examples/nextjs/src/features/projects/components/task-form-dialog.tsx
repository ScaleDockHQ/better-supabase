"use client";

import { useActionForm } from "better-supabase/react";
import { PlusIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useState } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import {
  Combobox,
  ComboboxContent,
  ComboboxEmpty,
  ComboboxInput,
  ComboboxItem,
  ComboboxList,
} from "@/components/ui/combobox";
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

import type { MemberOption, ProjectOption, TaskStatus } from "../project-types";

import { createTask } from "../project-actions";
import { TASK_STATUSES } from "../project-types";
import { useStatusLabel } from "../use-task-labels";

// #region recipe:record-form
interface ReferenceOption {
  readonly value: string;
  readonly label: string;
}

/**
 * A searchable picker for a foreign key, such as `tasks.project_id`. It posts
 * the id in a hidden input, so the form stays a plain server action form.
 */
function ReferenceCombobox({
  id,
  name,
  options,
  defaultValue,
  placeholder,
  empty,
}: {
  id: string;
  name: string;
  options: readonly ReferenceOption[];
  defaultValue: string | null;
  placeholder: string;
  empty: string;
}) {
  const [value, setValue] = useState<ReferenceOption | null>(
    () => options.find((option) => option.value === defaultValue) ?? null,
  );

  return (
    <>
      <input type="hidden" name={name} value={value?.value ?? ""} />
      <Combobox
        items={options}
        value={value}
        onValueChange={setValue}
        itemToStringLabel={(option: ReferenceOption) => option.label}
        isItemEqualToValue={(a: ReferenceOption, b: ReferenceOption) =>
          a.value === b.value
        }
      >
        <ComboboxInput id={id} placeholder={placeholder} showClear />
        <ComboboxContent>
          <ComboboxEmpty>{empty}</ComboboxEmpty>
          <ComboboxList>
            {(option: ReferenceOption) => (
              <ComboboxItem key={option.value} value={option}>
                {option.label}
              </ComboboxItem>
            )}
          </ComboboxList>
        </ComboboxContent>
      </Combobox>
    </>
  );
}

/**
 * The create form for a task. Each column gets the input its type and format
 * call for: text with its `max`, a select for `options`, a date input for
 * `date`, and a combobox for each reference.
 */
export function TaskFormDialog({
  projects,
  members,
  defaultProjectId,
}: {
  projects: readonly ProjectOption[];
  members: readonly MemberOption[];
  defaultProjectId: string | null;
}) {
  const t = useExtracted("projects");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const statusLabel = useStatusLabel();
  const [open, setOpen] = useState(false);
  const [status, setStatus] = useState<TaskStatus>("todo");

  const form = useActionForm(createTask, {
    onSuccess: () => {
      toast.success(t("Task created"));
      setOpen(false);
    },
  });

  const error = form.error === undefined ? null : errorMessage(form.error);

  const statusItems = TASK_STATUSES.map((value) => ({
    value,
    label: statusLabel(value),
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
        {t("New task")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <DialogHeader>
            <DialogTitle>{t("New task")}</DialogTitle>
            <DialogDescription>
              {t("It goes to the end of its status column.")}
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
              <FieldLabel htmlFor={`${fieldId}-project`}>
                {t("Project")}
              </FieldLabel>
              <ReferenceCombobox
                id={`${fieldId}-project`}
                name="projectId"
                options={projects.map((project) => ({
                  value: project.id,
                  label: project.name,
                }))}
                defaultValue={defaultProjectId}
                placeholder={t("Pick a project")}
                empty={t("No projects match.")}
              />
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-status`}>
                {t("Status")}
              </FieldLabel>
              <input type="hidden" name="status" value={status} />
              <Select
                value={status}
                items={statusItems}
                onValueChange={(value) => {
                  setStatus(
                    TASK_STATUSES.find((each) => each === value) ?? "todo",
                  );
                }}
              >
                <SelectTrigger id={`${fieldId}-status`}>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {statusItems.map((item) => (
                    <SelectItem key={item.value} value={item.value}>
                      {item.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-assignee`}>
                {t("Assignee")}
              </FieldLabel>
              <ReferenceCombobox
                id={`${fieldId}-assignee`}
                name="assigneeId"
                options={members.map((member) => ({
                  value: member.userId,
                  label: member.name,
                }))}
                defaultValue={null}
                placeholder={t("Unassigned")}
                empty={t("No members match.")}
              />
            </Field>
            <div className="grid grid-cols-2 gap-4">
              <Field>
                <FieldLabel htmlFor={`${fieldId}-starts`}>
                  {t("Starts on")}
                </FieldLabel>
                <Input id={`${fieldId}-starts`} name="startsOn" type="date" />
              </Field>
              <Field>
                <FieldLabel htmlFor={`${fieldId}-due`}>
                  {t("Due on")}
                </FieldLabel>
                <Input id={`${fieldId}-due`} name="dueOn" type="date" />
              </Field>
            </div>
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={form.pending}>
              {t("Create task")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
// #endregion recipe:record-form
