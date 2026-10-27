// #region recipe:invite-dialog
"use client";

import type { SubmitEvent } from "react";

import { CopyIcon, UserPlusIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useState } from "react";
import { toast } from "sonner";
import * as v from "valibot";

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
import { SubmitLabel } from "@/features/offline/components/submit-label";
import { invitationSent } from "@/features/organization/organization-actions";
import { useInviteLink } from "@/features/organization/use-invite-link";
import { useRoleLabel } from "@/features/organization/use-role-label";
import { useInvitations } from "@/hooks/use-organizations";
import { Role } from "@/lib/claims";
import { blockConfig } from "@/lib/supabase/blocks.generated";
import { useErrorMessage } from "@/lib/use-error-message";

/**
 * Invites a teammate through `invite_member` in the browser, then shows the
 * accept link: the example has no mailer.
 */
export function InviteMemberDialog({
  organizationId,
  assignable,
}: {
  organizationId: string;
  assignable: readonly Role[];
}) {
  const t = useExtracted("organization");
  const fieldId = useId();
  const roleLabel = useRoleLabel();
  const errorMessage = useErrorMessage();
  const inviteLink = useInviteLink();
  const [open, setOpen] = useState(false);
  const [email, setEmail] = useState("");
  const [role, setRole] = useState<Role>("member");

  const roles = assignable.map((each) => ({
    value: each,
    label: roleLabel(each),
  }));

  // The server renders the pending list; `invitationSent` renders it again.
  const { invite, inviting, sent, error, clear } = useInvitations({
    organizationId,
    schema: blockConfig.organizations.api,
    onChanged: async ({ kind }) => {
      if (kind === "invited") {
        await invitationSent({});
      }
    },
  });

  const link = sent ? inviteLink(sent.token) : null;

  const message =
    error === undefined
      ? null
      : error.kind === "conflict"
        ? t("That person is already a member or invited.")
        : errorMessage(error);

  const submit = async (event: SubmitEvent<HTMLFormElement>) => {
    event.preventDefault();
    await invite({ email: email.trim().toLowerCase(), role });
  };

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);
        setEmail("");

        if (!next) {
          clear();
        }
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
          <form onSubmit={(event) => void submit(event)} className="grid gap-6">
            <DialogHeader>
              <DialogTitle>{t("Invite a teammate")}</DialogTitle>
              <DialogDescription>
                {t(
                  "They join with the role you pick. You can't give a role above your own.",
                )}
              </DialogDescription>
            </DialogHeader>
            <FieldGroup>
              <Field data-invalid={message ? true : undefined}>
                <FieldLabel htmlFor={`${fieldId}-invite-email`}>
                  {t("Email")}
                </FieldLabel>
                <Input
                  id={`${fieldId}-invite-email`}
                  name="email"
                  type="email"
                  value={email}
                  onChange={(event) => {
                    setEmail(event.target.value);
                  }}
                  required
                  autoComplete="off"
                />
                {message ? <FieldError>{message}</FieldError> : null}
              </Field>
              <Field>
                <FieldLabel htmlFor={`${fieldId}-invite-role`}>
                  {t("Role")}
                </FieldLabel>
                <Select
                  value={role}
                  items={roles}
                  onValueChange={(value) => {
                    if (v.is(Role, value)) {
                      setRole(value);
                    }
                  }}
                >
                  <SelectTrigger id={`${fieldId}-invite-role`} className="w-40">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {roles.map((each) => (
                      <SelectItem key={each.value} value={each.value}>
                        {each.label}
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
              <Button type="submit" disabled={inviting}>
                <SubmitLabel pending={inviting}>
                  {t("Send invitation")}
                </SubmitLabel>
              </Button>
            </DialogFooter>
          </form>
        )}
      </DialogContent>
    </Dialog>
  );
}
// #endregion recipe:invite-dialog
