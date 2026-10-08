"use client";

import { useAction } from "better-supabase/react";
import { PlusIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useRouter } from "@/i18n/navigation";
import { useErrorMessage } from "@/lib/use-error-message";

import { createDefinition } from "../builder-actions";

export function CreateDefinitionForm() {
  const t = useExtracted("workflows");
  const router = useRouter();
  const errorMessage = useErrorMessage();
  const create = useAction(createDefinition, {
    onSuccess: (id) => {
      router.push(`/workflows/builder/${id}`);
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });
  return (
    <form
      className="flex gap-2"
      action={(form) => {
        void create.run({ name: String(form.get("name") ?? "") });
      }}
    >
      <Input
        name="name"
        required
        maxLength={100}
        aria-label={t("Workflow name")}
        placeholder={t("Workflow name")}
        className="w-56"
      />
      <Button type="submit" disabled={create.pending}>
        <PlusIcon />
        {t("New workflow")}
      </Button>
    </form>
  );
}
