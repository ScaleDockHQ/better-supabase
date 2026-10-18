"use client";

import { useAction } from "better-supabase/react";
import { CopyIcon, LinkIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useState } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Field, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { useErrorMessage } from "@/lib/use-error-message";

import { createBookingLink } from "../bookings-actions";

/** Creates a public link to the booking page and shows it once. */
export function BookingLinkButton() {
  const t = useExtracted("bookings");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [url, setUrl] = useState<string | null>(null);

  const create = useAction(createBookingLink, {
    onSuccess: ({ token }) => {
      setUrl(`${window.location.origin}/book/${token}`);
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <>
      <Button
        size="sm"
        variant="outline"
        disabled={create.pending}
        onClick={() => void create.run({})}
      >
        <LinkIcon />
        {t("New link")}
      </Button>
      <Dialog
        open={url !== null}
        onOpenChange={(open) => {
          if (!open) {
            setUrl(null);
          }
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{t("Your booking link")}</DialogTitle>
            <DialogDescription>
              {t(
                "Copy it now. It isn't shown again; make a new one if you lose it.",
              )}
            </DialogDescription>
          </DialogHeader>
          <Field>
            <FieldLabel htmlFor={`${fieldId}-url`}>{t("Link")}</FieldLabel>
            <div className="flex items-center gap-2">
              <Input id={`${fieldId}-url`} readOnly value={url ?? ""} />
              <Button
                size="icon-sm"
                variant="outline"
                aria-label={t("Copy link")}
                onClick={() => {
                  if (url) {
                    void navigator.clipboard
                      .writeText(url)
                      .then(() => toast.success(t("Link copied")));
                  }
                }}
              >
                <CopyIcon />
              </Button>
            </div>
          </Field>
        </DialogContent>
      </Dialog>
    </>
  );
}
