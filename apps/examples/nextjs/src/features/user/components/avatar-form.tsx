"use client";

import { useActionForm, useImage } from "better-supabase/react";
import { UploadIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useMemo } from "react";
import { toast } from "sonner";

import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import {
  Field,
  FieldDescription,
  FieldError,
  FieldLabel,
} from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { avatars } from "@/lib/buckets";
import { useSupabase } from "@/lib/hooks";
import { initials } from "@/lib/initials";
import { useErrorMessage } from "@/lib/use-error-message";

import { uploadAvatar } from "../user-actions";

export function AvatarForm({
  avatarPath,
  avatarUrl,
  name,
  email,
}: {
  avatarPath: string | null;
  avatarUrl: string | null;
  name: string | null;
  email: string | null;
}) {
  const t = useExtracted("user");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const supabase = useSupabase();
  const storage = useMemo(() => avatars.connect(supabase), [supabase]);
  const image = useImage(storage, avatarPath, "md");
  const src = image.src ?? avatarUrl;

  const form = useActionForm(uploadAvatar, {
    onSuccess: () => {
      toast.success(t("Avatar updated"));
    },
  });

  const error = form.error === undefined ? null : errorMessage(form.error);

  return (
    <form {...form.formProps} className="flex items-start gap-4">
      <Avatar className="size-16" data-testid="profile-avatar">
        {src ? <AvatarImage src={src} srcSet={image.srcSet} alt="" /> : null}
        <AvatarFallback className="text-lg">
          {initials(name, email)}
        </AvatarFallback>
      </Avatar>
      <div className="flex-1 space-y-3">
        <Field data-invalid={error ? true : undefined}>
          <FieldLabel htmlFor={`${fieldId}-avatar`}>{t("Avatar")}</FieldLabel>
          <Input
            id={`${fieldId}-avatar`}
            type="file"
            name="avatar"
            accept="image/png,image/jpeg,image/webp,image/gif,image/avif"
            required
          />
          <FieldDescription>
            {t("PNG, JPEG, WebP, GIF or AVIF, up to 2 MB.")}
          </FieldDescription>
          {error ? <FieldError>{error}</FieldError> : null}
        </Field>
        <Button
          type="submit"
          variant="outline"
          size="sm"
          disabled={form.pending}
        >
          <UploadIcon />
          {t("Upload avatar")}
        </Button>
      </div>
    </form>
  );
}
