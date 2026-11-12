"use client";

import type { ActionResultOf } from "better-supabase/react";

import { useActionForm } from "better-supabase/react";
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
import { Textarea } from "@/components/ui/textarea";
import { FormSelect } from "@/features/crm/components/form-select";
import { useRouter, toAppHref } from "@/i18n/navigation";
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

/** One form field, described as data so a server page can declare a form. */
export interface DialogField {
  readonly name: string;
  readonly label: string;
  readonly kind: "text" | "textarea" | "date" | "decimal" | "number" | "select";
  readonly required?: boolean;
  readonly placeholder?: string;
  readonly defaultValue?: string;
  readonly options?: readonly {
    readonly value: string;
    readonly label: string;
  }[];
}

type DialogAction = (
  input: FormData,
) => Promise<ActionResultOf<{ readonly id?: string } | boolean | object>>;

/**
 * A button that opens a dialog with a form over one Server Action. The page
 * declares the fields; `redirectTo` is a path with `{id}` for the new record's
 * id, and `hidden` carries ids the action needs.
 */
export function ActionDialog({
  action,
  title,
  description,
  trigger,
  submitLabel,
  successMessage,
  fields,
  hidden,
  redirectTo,
  variant = "default",
}: {
  action: DialogAction;
  title: string;
  description?: string;
  trigger: string;
  submitLabel: string;
  successMessage: string;
  fields: readonly DialogField[];
  hidden?: Readonly<Record<string, string>>;
  redirectTo?: string;
  variant?: "default" | "outline";
}) {
  const t = useExtracted("sales");
  const router = useRouter();
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);

  const form = useActionForm(action, {
    onSuccess: (data) => {
      setOpen(false);
      toast.success(successMessage);

      // oxlint-disable-next-line anti-slop/no-runtime-typeof -- an action's data is whatever it returns; a created record has an id.
      const id = typeof data === "object" && "id" in data ? data.id : undefined;

      if (redirectTo !== undefined && id !== undefined) {
        router.push(toAppHref(redirectTo.replace("{id}", id)));
      }
    },
  });

  const error = form.error === undefined ? null : errorMessage(form.error);

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger render={<Button size="sm" variant={variant} />}>
        <PlusIcon />
        {trigger}
      </DialogTrigger>
      <DialogContent>
        <form
          {...form.formProps}
          className="grid max-h-[calc(100dvh-6rem)] gap-6 overflow-y-auto"
        >
          <DialogHeader>
            <DialogTitle>{title}</DialogTitle>
            {description ? (
              <DialogDescription>{description}</DialogDescription>
            ) : null}
          </DialogHeader>
          {Object.entries(hidden ?? {}).map(([name, value]) => (
            <input key={name} type="hidden" name={name} value={value} />
          ))}
          <FieldGroup>
            {fields.map((field) => {
              const id = `${fieldId}-${field.name}`;
              const message = form.fieldErrors[field.name];

              return (
                <Field
                  key={field.name}
                  data-invalid={message ? true : undefined}
                >
                  <FieldLabel htmlFor={id}>{field.label}</FieldLabel>
                  {field.kind === "select" ? (
                    <FormSelect
                      id={id}
                      name={field.name}
                      items={field.options ?? []}
                      defaultValue={
                        field.defaultValue ?? field.options?.[0]?.value ?? ""
                      }
                    />
                  ) : field.kind === "textarea" ? (
                    <Textarea
                      id={id}
                      name={field.name}
                      required={field.required === true}
                      maxLength={2000}
                      {...(field.placeholder === undefined
                        ? {}
                        : { placeholder: field.placeholder })}
                    />
                  ) : (
                    <Input
                      id={id}
                      name={field.name}
                      required={field.required === true}
                      type={
                        field.kind === "date"
                          ? "date"
                          : field.kind === "number"
                            ? "number"
                            : "text"
                      }
                      {...(field.kind === "decimal"
                        ? {
                            inputMode: "decimal" as const,
                            pattern: "\\d+(\\.\\d{1,2})?",
                          }
                        : {})}
                      {...(field.placeholder === undefined
                        ? {}
                        : { placeholder: field.placeholder })}
                      {...(field.defaultValue === undefined
                        ? {}
                        : { defaultValue: field.defaultValue })}
                      aria-invalid={message ? true : undefined}
                    />
                  )}
                  {message ? <FieldError>{message}</FieldError> : null}
                </Field>
              );
            })}
            {error ? <FieldError>{error}</FieldError> : null}
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={form.pending}>
              {submitLabel}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
