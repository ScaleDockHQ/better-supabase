"use client";

import { useAction } from "better-supabase/react";
import {
  ArrowDownIcon,
  ArrowUpIcon,
  PencilIcon,
  PlusIcon,
  Trash2Icon,
} from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useState, useTransition } from "react";
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
  FieldDescription,
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
import { usePathname, useRouter } from "@/i18n/navigation";
import { useErrorMessage } from "@/lib/use-error-message";

import type { FieldEntity, FieldRow, FieldType } from "../custom-fields-types";

import { deleteField, moveField, saveField } from "../custom-fields-actions";
import { FIELD_ENTITIES, FIELD_TYPES } from "../custom-fields-types";

function useEntityLabel(): (entity: FieldEntity) => string {
  const t = useExtracted("custom-fields");

  return (entity) => {
    switch (entity) {
      case "customer": {
        return t("Customers");
      }

      case "work_item": {
        return t("Work items");
      }

      default: {
        const unknown: never = entity;

        return unknown;
      }
    }
  };
}

export function useTypeLabel(): (type: string) => string {
  const t = useExtracted("custom-fields");

  return (type) => {
    const known = FIELD_TYPES.find((each) => each === type);

    if (known === undefined) {
      return type;
    }

    switch (known) {
      case "text": {
        return t("Text");
      }

      case "number": {
        return t("Number");
      }

      case "date": {
        return t("Date");
      }

      case "bool": {
        return t("Yes or no");
      }

      case "option": {
        return t("Option");
      }

      case "json": {
        return t("JSON");
      }

      case "email": {
        return t("Email");
      }

      case "url": {
        return t("Link");
      }

      case "multi_option": {
        return t("Options");
      }

      case "user": {
        return t("Person");
      }

      case "rating": {
        return t("Rating");
      }

      case "currency": {
        return t("Amount");
      }

      case "phone_e164": {
        return t("Phone number");
      }

      case "bsn": {
        return t("BSN");
      }

      case "iban": {
        return t("IBAN");
      }

      default: {
        const unknown: never = known;

        return unknown;
      }
    }
  };
}

/** Switches the editor between entities through `?entity=`. */
export function EntityPicker({ entity }: { entity: FieldEntity }) {
  const t = useExtracted("custom-fields");
  const router = useRouter();
  const pathname = usePathname();
  const entityLabel = useEntityLabel();
  const [switching, startTransition] = useTransition();

  const items = FIELD_ENTITIES.map((each) => ({
    value: each,
    label: entityLabel(each),
  }));

  return (
    <Select
      value={entity}
      items={items}
      disabled={switching}
      onValueChange={(value) => {
        const next = FIELD_ENTITIES.find((each) => each === value);

        if (next) {
          startTransition(() => {
            router.replace(`${pathname}?entity=${next}`);
          });
        }
      }}
    >
      <SelectTrigger size="sm" className="w-40" aria-label={t("Record type")}>
        <SelectValue />
      </SelectTrigger>
      <SelectContent>
        {items.map((item) => (
          <SelectItem key={item.value} value={item.value}>
            {item.label}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}

/** Adds a field, or relabels one when `field` is given. */
export function FieldDialog({
  entity,
  field,
}: {
  entity: FieldEntity;
  field?: FieldRow;
}) {
  const t = useExtracted("custom-fields");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const typeLabel = useTypeLabel();
  const [open, setOpen] = useState(false);
  const [key, setKey] = useState(field?.key ?? "");
  const [label, setLabel] = useState(field?.label ?? "");

  const [type, setType] = useState<FieldType>(
    () => FIELD_TYPES.find((each) => each === field?.type) ?? "text",
  );

  const [sensitive, setSensitive] = useState(field?.sensitive ?? false);

  const save = useAction(saveField, {
    onSuccess: () => {
      toast.success(field ? t("Field saved") : t("Field added"));
      setOpen(false);

      if (!field) {
        setKey("");
        setLabel("");
        setType("text");
        setSensitive(false);
      }
    },
  });

  const error = save.error === undefined ? null : errorMessage(save.error);

  const typeItems = FIELD_TYPES.map((each) => ({
    value: each,
    label: typeLabel(each),
  }));

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);

        if (!next) {
          save.reset();
        }
      }}
    >
      {field ? (
        <DialogTrigger
          render={
            <Button
              size="icon-sm"
              variant="ghost"
              aria-label={t("Edit {label}", { label: field.label })}
            />
          }
        >
          <PencilIcon />
        </DialogTrigger>
      ) : (
        <DialogTrigger render={<Button size="sm" />}>
          <PlusIcon />
          {t("Add field")}
        </DialogTrigger>
      )}
      <DialogContent>
        <form
          className="grid gap-6"
          onSubmit={(event) => {
            event.preventDefault();
            void save.run({ entity, key, label, type, sensitive });
          }}
        >
          <DialogHeader>
            <DialogTitle>
              {field ? t("Edit field") : t("Add field")}
            </DialogTitle>
            <DialogDescription>
              {t(
                "Fields show on every record of this type, in the list order.",
              )}
            </DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-label`}>{t("Label")}</FieldLabel>
              <Input
                id={`${fieldId}-label`}
                value={label}
                required
                maxLength={80}
                autoComplete="off"
                onChange={(event) => {
                  setLabel(event.target.value);
                }}
              />
            </Field>
            <Field data-invalid={error ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-key`}>{t("Key")}</FieldLabel>
              <Input
                id={`${fieldId}-key`}
                value={key}
                required
                readOnly={field !== undefined}
                pattern="[a-z][a-z0-9_]*"
                maxLength={63}
                autoComplete="off"
                onChange={(event) => {
                  setKey(event.target.value);
                }}
              />
              <FieldDescription>
                {t(
                  "Lowercase letters, digits and underscores. It can't change later.",
                )}
              </FieldDescription>
              {error ? <FieldError>{error}</FieldError> : null}
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-type`}>{t("Type")}</FieldLabel>
              <Select
                value={type}
                items={typeItems}
                onValueChange={(value) => {
                  const next = FIELD_TYPES.find((each) => each === value);

                  if (next) {
                    setType(next);
                  }
                }}
              >
                <SelectTrigger id={`${fieldId}-type`}>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {typeItems.map((item) => (
                    <SelectItem key={item.value} value={item.value}>
                      {item.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
            <Field orientation="horizontal">
              <Checkbox
                id={`${fieldId}-sensitive`}
                checked={sensitive}
                onCheckedChange={(checked) => {
                  setSensitive(checked);
                }}
              />
              <FieldLabel htmlFor={`${fieldId}-sensitive`}>
                {t(
                  "Sensitive: only members who can read sensitive fields see it",
                )}
              </FieldLabel>
            </Field>
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={save.pending}>
              {field ? t("Save") : t("Add field")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

/** Move up, move down and delete for one field. */
export function FieldRowControls({
  entity,
  field,
  first,
  last,
}: {
  entity: FieldEntity;
  field: FieldRow;
  first: boolean;
  last: boolean;
}) {
  const t = useExtracted("custom-fields");
  const errorMessage = useErrorMessage();
  const [confirming, setConfirming] = useState(false);

  const onError = (error: Parameters<typeof errorMessage>[0]) => {
    toast.error(errorMessage(error));
  };

  const move = useAction(moveField, { onError });

  const remove = useAction(deleteField, {
    onError,
    onSuccess: () => {
      toast.success(t("Field deleted"));
      setConfirming(false);
    },
  });

  const busy = move.pending || remove.pending;

  return (
    <div className="flex items-center justify-end gap-1">
      <Button
        size="icon-sm"
        variant="ghost"
        disabled={first || busy}
        aria-label={t("Move {label} up", { label: field.label })}
        onClick={() => {
          void move.run({ entity, id: field.id, direction: "up" });
        }}
      >
        <ArrowUpIcon />
      </Button>
      <Button
        size="icon-sm"
        variant="ghost"
        disabled={last || busy}
        aria-label={t("Move {label} down", { label: field.label })}
        onClick={() => {
          void move.run({ entity, id: field.id, direction: "down" });
        }}
      >
        <ArrowDownIcon />
      </Button>
      <FieldDialog entity={entity} field={field} />
      <AlertDialog
        open={confirming}
        onOpenChange={(next) => {
          if (!remove.pending) {
            setConfirming(next);
          }
        }}
      >
        <AlertDialogTrigger
          render={
            <Button
              type="button"
              size="icon-sm"
              variant="ghost"
              disabled={busy}
              aria-label={t("Delete {label}", { label: field.label })}
            />
          }
        >
          <Trash2Icon />
        </AlertDialogTrigger>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              {t("Delete {label}?", { label: field.label })}
            </AlertDialogTitle>
            <AlertDialogDescription>
              {t("Every value saved in this field is deleted with it.")}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={remove.pending}>
              {t("Cancel")}
            </AlertDialogCancel>
            <AlertDialogAction
              type="button"
              variant="destructive"
              disabled={remove.pending}
              onClick={() => {
                void remove.run({ id: field.id });
              }}
            >
              {t("Delete")}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
