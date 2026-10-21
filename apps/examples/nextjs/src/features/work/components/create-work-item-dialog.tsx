"use client";

// #region recipe:entity-form
import type { EntityFormInput } from "better-supabase/records";

import { workItemInputSchema } from "better-supabase/blocks/work-items";
import { useAction, useEntityForm } from "better-supabase/react";
import { entityForm } from "better-supabase/records";
import { PlusIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useMemo, useState } from "react";
import { toast } from "sonner";

import type { FieldRow } from "@/features/custom-fields/custom-fields-types";

import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
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

/** The HTML input type for each form input; the rest are text inputs. */
const INPUT_TYPES: Partial<Record<EntityFormInput, string>> = {
  number: "number",
  integer: "number",
  date: "date",
  datetime: "datetime-local",
  email: "email",
  url: "url",
};

/**
 * A dialog that creates a work item with a title, a team, a priority and the
 * organization's custom fields for work items. `entityForm` turns the entity
 * schema and the field definitions into one list of inputs and validates them
 * together.
 */
export function CreateWorkItemDialog({
  teams,
  defaultTeamId,
  customFields,
}: {
  teams: readonly TeamOption[];
  defaultTeamId: string | null;
  customFields: readonly FieldRow[];
}) {
  const t = useExtracted("work");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const priorityLabel = usePriorityLabel();
  const [open, setOpen] = useState(false);
  const [teamId, setTeamId] = useState(defaultTeamId ?? NO_TEAM);

  const definition = useMemo(
    () =>
      entityForm(workItemInputSchema, {
        fields: ["title", "priority"],
        customFields: customFields.map((field) => ({
          key: field.key,
          label: field.label,
          type: field.type,
          required: false,
          sensitive: field.sensitive,
        })),
      }),
    [customFields],
  );

  const create = useAction(createWorkItem, {
    onSuccess: (identifier) => {
      toast.success(t("Created {identifier}", { identifier }));
      setOpen(false);
    },
  });

  const form = useEntityForm(definition, {
    initial: { title: "", priority: "0" },
    onSubmit: async ({ input, custom }) => {
      await create.run({
        title: input.title,
        teamId,
        priority: input.priority ?? 0,
        custom: Object.fromEntries(
          Object.entries(custom).map(([key, value]) => [key, String(value)]),
        ),
      });
    },
  });

  const error = create.error === undefined ? null : errorMessage(create.error);
  const textOf = (key: string) => String(form.values[key] ?? "");

  const teamItems = [
    { value: NO_TEAM, label: t("No team") },
    ...teams.map((team) => ({ value: team.id, label: team.name })),
  ];

  const priorityItems = ["0", "1", "2", "3", "4"].map((value) => ({
    value,
    label: priorityLabel(Number(value)),
  }));

  const custom = definition.fields.filter((field) => field.source === "custom");

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);

        if (!next) {
          form.reset();
          create.reset();
        }
      }}
    >
      <DialogTrigger render={<Button size="sm" />}>
        <PlusIcon />
        {t("New item")}
      </DialogTrigger>
      <DialogContent>
        <form
          onSubmit={(event) => {
            void form.submit(event);
          }}
          className="grid gap-6"
        >
          <DialogHeader>
            <DialogTitle>{t("New work item")}</DialogTitle>
            <DialogDescription>
              {t("It starts in the first stage of your workflow.")}
            </DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field
              data-invalid={error || form.errors["title"] ? true : undefined}
            >
              <FieldLabel htmlFor={`${fieldId}-title`}>{t("Title")}</FieldLabel>
              <Input
                id={`${fieldId}-title`}
                name="title"
                required
                maxLength={200}
                autoComplete="off"
                value={textOf("title")}
                onChange={(event) => {
                  form.set("title", event.target.value);
                }}
              />
              {form.errors["title"] ? (
                <FieldError>{t("Enter a title.")}</FieldError>
              ) : null}
              {error ? <FieldError>{error}</FieldError> : null}
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-team`}>{t("Team")}</FieldLabel>
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
              <Select
                value={textOf("priority")}
                items={priorityItems}
                onValueChange={(value) => {
                  form.set("priority", value ?? "0");
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
            {custom.map((field) =>
              field.input === "bool" ? (
                <Field key={field.key} orientation="horizontal">
                  <Checkbox
                    id={`${fieldId}-${field.key}`}
                    checked={form.values[field.key] === true}
                    onCheckedChange={(checked) => {
                      form.set(field.key, checked);
                    }}
                  />
                  <FieldLabel htmlFor={`${fieldId}-${field.key}`}>
                    {field.label}
                  </FieldLabel>
                </Field>
              ) : (
                <Field
                  key={field.key}
                  data-invalid={form.errors[field.key] ? true : undefined}
                >
                  <FieldLabel htmlFor={`${fieldId}-${field.key}`}>
                    {field.label}
                  </FieldLabel>
                  <Input
                    id={`${fieldId}-${field.key}`}
                    type={INPUT_TYPES[field.input] ?? "text"}
                    autoComplete="off"
                    value={textOf(field.key)}
                    onChange={(event) => {
                      form.set(field.key, event.target.value);
                    }}
                  />
                  {form.errors[field.key] ? (
                    <FieldError>{form.errors[field.key]}</FieldError>
                  ) : null}
                </Field>
              ),
            )}
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={form.pending || create.pending}>
              {t("Create item")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
// #endregion recipe:entity-form
