"use client";

import { useErrorMessage } from "better-supabase/react";
import { LifeBuoyIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useState, useTransition } from "react";

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
import { Field, FieldLabel } from "@/components/ui/field";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "@/lib/toast";

import { viewAsMember } from "../support-actions";

/**
 * Views the app as one member. The session starts at once when a second admin
 * approved a request for the member; otherwise the request goes to /approvals.
 */
export function ViewAsMemberButton({
  userId,
  name,
}: {
  userId: string;
  name: string;
}) {
  const t = useExtracted("support");
  const reasonId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState("");
  const [pending, startTransition] = useTransition();

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger
        render={
          <Button
            variant="ghost"
            size="icon-sm"
            aria-label={t("View as {name}", { name })}
          />
        }
      >
        <LifeBuoyIcon />
      </DialogTrigger>
      <DialogContent>
        <form
          className="grid gap-6"
          onSubmit={(event) => {
            event.preventDefault();
            startTransition(async () => {
              const result = await viewAsMember({ target: userId, reason });

              if (!result.ok) {
                toast.error(errorMessage(result.error));

                return;
              }

              toast.success(
                result.data === "started"
                  ? t("Viewing as {name}", { name })
                  : t("Request sent for approval"),
              );
              setOpen(false);
              setReason("");
            });
          }}
        >
          <DialogHeader>
            <DialogTitle>{t("View as {name}", { name })}</DialogTitle>
            <DialogDescription>
              {t(
                "The session is read-only, expires on its own and is recorded in the audit log. A second platform admin approves it first.",
              )}
            </DialogDescription>
          </DialogHeader>
          <Field>
            <FieldLabel htmlFor={reasonId}>{t("Reason")}</FieldLabel>
            <Textarea
              id={reasonId}
              value={reason}
              required
              maxLength={500}
              onChange={(event) => {
                setReason(event.target.value);
              }}
            />
          </Field>
          <DialogFooter>
            <DialogClose render={<Button variant="outline" type="button" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={pending || reason.trim() === ""}>
              {t("View as member")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
