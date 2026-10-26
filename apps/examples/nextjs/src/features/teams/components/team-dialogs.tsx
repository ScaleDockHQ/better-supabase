"use client";

import { useActionForm } from "better-supabase/react";
import { PencilIcon, PlusIcon } from "lucide-react";
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
import { Textarea } from "@/components/ui/textarea";
import { useErrorMessage } from "@/lib/use-error-message";

import { createTeam, updateTeam } from "../teams-actions";

function TeamFields({
  error,
  name,
  description,
}: {
  error: string | null;
  name?: string;
  description?: string | null;
}) {
  const t = useExtracted("teams");
  const fieldId = useId();

  return (
    <FieldGroup>
      <Field data-invalid={error ? true : undefined}>
        <FieldLabel htmlFor={`${fieldId}-name`}>{t("Name")}</FieldLabel>
        <Input
          id={`${fieldId}-name`}
          name="name"
          required
          maxLength={80}
          autoComplete="off"
          defaultValue={name}
          aria-invalid={error ? true : undefined}
        />
        {error ? <FieldError>{error}</FieldError> : null}
      </Field>
      <Field>
        <FieldLabel htmlFor={`${fieldId}-description`}>
          {t("Description")}
        </FieldLabel>
        <Textarea
          id={`${fieldId}-description`}
          name="description"
          maxLength={280}
          defaultValue={description ?? ""}
        />
      </Field>
    </FieldGroup>
  );
}

/** Creates a team in the active organization. */
export function CreateTeamDialog() {
  const t = useExtracted("teams");
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);

  const form = useActionForm(createTeam, {
    onSuccess: () => {
      setOpen(false);
      toast.success(t("Team created"));
    },
  });

  const error = form.error === undefined ? null : errorMessage(form.error);

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger render={<Button size="sm" />}>
        <PlusIcon />
        {t("New team")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <DialogHeader>
            <DialogTitle>{t("New team")}</DialogTitle>
            <DialogDescription>
              {t("Teams group members and can own customers.")}
            </DialogDescription>
          </DialogHeader>
          <TeamFields error={error} />
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={form.pending}>
              {t("Create")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

/** Renames a team and changes its description. */
export function EditTeamDialog({
  id,
  name,
  description,
}: {
  id: string;
  name: string;
  description: string | null;
}) {
  const t = useExtracted("teams");
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);

  const form = useActionForm(updateTeam, {
    onSuccess: () => {
      setOpen(false);
      toast.success(t("Team updated"));
    },
  });

  const error = form.error === undefined ? null : errorMessage(form.error);

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger render={<Button size="sm" variant="outline" />}>
        <PencilIcon />
        {t("Edit")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <input type="hidden" name="id" value={id} />
          <DialogHeader>
            <DialogTitle>{t("Edit team")}</DialogTitle>
            <DialogDescription>
              {t("The slug stays the same when you rename a team.")}
            </DialogDescription>
          </DialogHeader>
          <TeamFields error={error} name={name} description={description} />
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={form.pending}>
              {t("Save")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
