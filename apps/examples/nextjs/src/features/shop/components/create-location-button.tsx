"use client";

import { useAction } from "better-supabase/react";
import { WarehouseIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { useErrorMessage } from "@/lib/use-error-message";

import { createMainLocation } from "../shop-actions";

export function CreateLocationButton() {
  const t = useExtracted("shop");
  const errorMessage = useErrorMessage();

  const create = useAction(createMainLocation, {
    onSuccess: () => {
      toast.success(t("Location created"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <Button
      size="sm"
      disabled={create.pending}
      onClick={() => {
        void create.run({});
      }}
    >
      <WarehouseIcon />
      {t("Add a main warehouse")}
    </Button>
  );
}
