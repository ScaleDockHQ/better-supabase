"use client";

import { useActionForm } from "better-supabase/react";
import { CopyIcon, UserPlusIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useState } from "react";
import { toast } from "sonner";

import type { Role } from "@/lib/claims";

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
import { assignableRoles } from "@/features/user/user-permissions";
import { useErrorMessage } from "@/lib/use-error-message";

import { inviteMember } from "../organization-actions";
import { useInviteLink } from "../use-invite-link";
import { useRoleLabel } from "../use-role-label";

export function InviteMemberDialog({ myRole }: { myRole: Role }) {
  const t = useExtracted("organization");
  const fieldId = useId();
  const roleLabel = useRoleLabel();
  const errorMessage = useErrorMessage();
  const inviteLink = useInviteLink();
  const [open, setOpen] = useState(false);
  const roles = assignableRoles(myRole).map((role) => ({
    value: role,
    label: roleLabel(role),
  }));
  const form = useActionForm(inviteMember);
  const link = form.data ? inviteLink(form.data.token) : null;
  const error =
    form.error === undefined
      ? null
      : form.error.kind === "conflict"
        ? t("That person is already a member or invited.")
        : errorMessage(form.error);

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);
        if (!next) form.reset();
      }}
    >
      <DialogTrigger render={<Button size="sm" />}>
        <UserPlusIcon />
        {t("Invite")}
      </DialogTrigger>
      <DialogContent>
        {link ? (
          <div className="grid gap-6">
            <DialogHeader>
              <DialogTitle>{t("Invitation created")}</DialogTitle>
              <DialogDescription>
                {t("Send this link. It works once and expires in seven days.")}
              </DialogDescription>
            </DialogHeader>
            <div className="flex gap-2">
              <Input
                value={link}
                readOnly
                aria-label={t("Invitation link")}
                data-testid="invite-link"
              />
              <Button
                variant="outline"
                size="icon"
                aria-label={t("Copy link")}
                onClick={() => {
                  void navigator.clipboard
                    .writeText(link)
                    .then(() => toast.success(t("Link copied")));
                }}
              >
                <CopyIcon />
              </Button>
            </div>
            <DialogFooter>
              <DialogClose render={<Button />}>{t("Done")}</DialogClose>
            </DialogFooter>
          </div>
        ) : (
          <form {...form.formProps} className="grid gap-6">
            <DialogHeader>
              <DialogTitle>{t("Invite a teammate")}</DialogTitle>
              <DialogDescription>
                {t(
                  "They join with the role you pick. You can't give a role above your own.",
                )}
              </DialogDescription>
            </DialogHeader>
            <FieldGroup>
              <Field data-invalid={error ? true : undefined}>
                <FieldLabel htmlFor={`${fieldId}-invite-email`}>
                  {t("Email")}
                </FieldLabel>
                <Input
                  id={`${fieldId}-invite-email`}
                  name="email"
                  type="email"
                  required
                  autoComplete="off"
                />
                {error ? <FieldError>{error}</FieldError> : null}
              </Field>
              <Field>
                <FieldLabel htmlFor={`${fieldId}-invite-role`}>
                  {t("Role")}
                </FieldLabel>
                <Select name="role" defaultValue="member" items={roles}>
                  <SelectTrigger id={`${fieldId}-invite-role`} className="w-40">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {roles.map((role) => (
                      <SelectItem key={role.value} value={role.value}>
                        {role.label}
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
                {t("Send invitation")}
              </Button>
            </DialogFooter>
          </form>
        )}
      </DialogContent>
    </Dialog>
  );
}
