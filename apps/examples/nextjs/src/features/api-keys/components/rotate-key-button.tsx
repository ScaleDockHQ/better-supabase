"use client";

import { useAction, useErrorMessage } from "better-supabase/react";
import { RefreshCwIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useState } from "react";

import { Alert, AlertDescription, AlertTitle } from "@/components/reui/alert";
import { Button } from "@/components/ui/button";
import { toast } from "@/lib/toast";

import { rotateKey } from "../../composites/composites-actions";

const GRACE_HOURS = 24;

/**
 * Rotates the key through `saas.rotateApiKey`: a new key replaces it and the
 * old token keeps working for a grace period. The new token is shown once.
 */
export function RotateKeyButton({ id }: { id: string }) {
  const t = useExtracted("apiKeys");
  const errorMessage = useErrorMessage();
  const [token, setToken] = useState<string | undefined>();

  const rotate = useAction(rotateKey, {
    onSuccess: (data) => {
      setToken(data.token);
      toast.success(t("Key rotated"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap gap-2">
        <Button
          size="sm"
          disabled={rotate.pending}
          onClick={() => {
            void rotate.run({ id, graceHours: GRACE_HOURS });
          }}
        >
          <RefreshCwIcon />
          {t("Rotate, keep the old key {hours, number} hours", {
            hours: GRACE_HOURS,
          })}
        </Button>
        <Button
          size="sm"
          variant="outline"
          disabled={rotate.pending}
          onClick={() => {
            void rotate.run({ id, graceHours: 0 });
          }}
        >
          {t("Rotate now")}
        </Button>
      </div>
      {token === undefined ? null : (
        <Alert data-testid="rotated-token">
          <AlertTitle>{t("Copy the new token now")}</AlertTitle>
          <AlertDescription>
            <code className="font-mono text-xs break-all">{token}</code>
          </AlertDescription>
        </Alert>
      )}
    </div>
  );
}
