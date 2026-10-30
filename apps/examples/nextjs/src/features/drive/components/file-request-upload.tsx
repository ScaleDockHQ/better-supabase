"use client";

import { useActionForm } from "better-supabase/react";
import { CircleCheckIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useState } from "react";

import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import {
  Field,
  FieldDescription,
  FieldError,
  FieldGroup,
  FieldLabel,
} from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { useErrorMessage } from "@/lib/use-error-message";

import { sendToFileRequest } from "../drive-request-actions";

// #region recipe:file-request-upload
/**
 * The public page of a file request link: pick a file and send it into the
 * folder, with the link's password when it has one. The sender never sees what
 * the folder holds.
 */
export function FileRequestUpload({ token }: { token: string }) {
  const t = useExtracted("drive");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [password, setPassword] = useState<"none" | "asked" | "wrong">("none");
  const [sent, setSent] = useState<string | null>(null);

  const form = useActionForm(sendToFileRequest, {
    resetOnSuccess: false,
    onSuccess: (result, element) => {
      if (result.passwordRequired) {
        setPassword((current) => (current === "none" ? "asked" : "wrong"));

        return;
      }

      element.reset();
      setSent(result.name);
    },
  });

  const error = form.error === undefined ? null : errorMessage(form.error);
  const locked = password !== "none";
  const wrongPassword = password === "wrong";

  return (
    <Card data-recipe="file-request-upload">
      <CardHeader>
        <CardTitle>{t("Send files")}</CardTitle>
        <CardDescription>
          {t("Files you send go straight to the folder's owner.")}
        </CardDescription>
      </CardHeader>
      <CardContent>
        {sent === null ? (
          <form {...form.formProps} className="flex flex-col gap-4">
            <input type="hidden" name="token" value={token} />
            <FieldGroup>
              <Field data-invalid={form.fieldErrors["file"] ? true : undefined}>
                <FieldLabel htmlFor={`${fieldId}-file`}>{t("File")}</FieldLabel>
                <Input
                  id={`${fieldId}-file`}
                  name="file"
                  type="file"
                  required
                />
                <FieldDescription>{t("Up to 1 MB per file.")}</FieldDescription>
              </Field>
              {locked ? (
                <Field data-invalid={wrongPassword ? true : undefined}>
                  <FieldLabel htmlFor={`${fieldId}-password`}>
                    {t("Password")}
                  </FieldLabel>
                  <Input
                    id={`${fieldId}-password`}
                    name="password"
                    type="password"
                    required
                    maxLength={200}
                    autoComplete="off"
                  />
                  {wrongPassword ? (
                    <FieldError>
                      {t(
                        "This link needs its password. Check it and try again.",
                      )}
                    </FieldError>
                  ) : null}
                </Field>
              ) : null}
              {error ? <FieldError>{error}</FieldError> : null}
            </FieldGroup>
            <div className="flex justify-end">
              <Button type="submit" disabled={form.pending}>
                {t("Send")}
              </Button>
            </div>
          </form>
        ) : (
          <Empty className="border">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <CircleCheckIcon />
              </EmptyMedia>
              <EmptyTitle>{t("File sent")}</EmptyTitle>
              <EmptyDescription>{sent}</EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <Badge variant="success-light">{t("Received")}</Badge>
              <Button
                variant="outline"
                onClick={() => {
                  form.reset();
                  setSent(null);
                }}
              >
                {t("Send another file")}
              </Button>
            </EmptyContent>
          </Empty>
        )}
      </CardContent>
    </Card>
  );
}
// #endregion recipe:file-request-upload

export function FileRequestUploadSkeleton() {
  return (
    <Card>
      <CardHeader>
        <Skeleton className="h-5 w-32" />
        <Skeleton className="h-4 w-56" />
      </CardHeader>
      <CardContent className="flex flex-col gap-4">
        <Skeleton className="h-4 w-16" />
        <Skeleton className="h-8 w-full" />
        <Skeleton className="h-8 w-20 self-end" />
      </CardContent>
    </Card>
  );
}
