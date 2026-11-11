"use client";

import type { ActionInputOf, ActionResultOf } from "better-supabase/react";

import { useAction } from "better-supabase/react";

import { Button } from "@/components/ui/button";
import { useRouter, toAppHref } from "@/i18n/navigation";
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

/**
 * A button that runs one Server Action with a fixed input, toasts the result
 * and, with `redirectTo`, navigates afterwards (for a delete).
 */
export function ActionButton<Input>({
  action,
  input,
  label,
  successMessage,
  variant = "outline",
  redirectTo,
}: {
  action: (input: Input) => Promise<ActionResultOf<unknown>>;
  input: ActionInputOf<Input>;
  label: string;
  successMessage: string;
  variant?: "default" | "outline" | "ghost" | "destructive";
  redirectTo?: string;
}) {
  const router = useRouter();
  const errorMessage = useErrorMessage();

  const handle = useAction(action, {
    onSuccess: () => {
      toast.success(successMessage);

      if (redirectTo !== undefined) {
        router.push(toAppHref(redirectTo));
      }
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <Button
      type="button"
      size="sm"
      variant={variant}
      disabled={handle.pending}
      onClick={() => {
        void handle.run(input);
      }}
    >
      {label}
    </Button>
  );
}
