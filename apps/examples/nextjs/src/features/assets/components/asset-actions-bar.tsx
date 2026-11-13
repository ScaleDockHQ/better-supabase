"use client";

import { useAction, useErrorMessage } from "better-supabase/react";
import { useExtracted } from "next-intl";

import { Button } from "@/components/ui/button";
import { toast } from "@/lib/toast";

import type { AssetRow } from "../asset-row";

import { releaseAsset, setAssetStatus } from "../assets-actions";

/** Status changes and release on the asset detail head. */
export function AssetActionsBar({
  assetId,
  status,
  canManage,
  canAssign,
}: {
  assetId: string;
  status: AssetRow["status"];
  canManage: boolean;
  canAssign: boolean;
}) {
  const t = useExtracted("assets");
  const errorMessage = useErrorMessage();

  const options = {
    onSuccess: () => {
      toast.success(t("Asset updated"));
    },
    onError: (error: Parameters<typeof errorMessage>[0]) => {
      toast.error(errorMessage(error));
    },
  };

  const setStatus = useAction(setAssetStatus, options);
  const release = useAction(releaseAsset, options);

  return (
    <>
      {canAssign ? (
        <Button
          size="sm"
          variant="outline"
          disabled={release.pending}
          onClick={() => {
            void release.run({ assetId });
          }}
        >
          {t("Release")}
        </Button>
      ) : null}
      {canManage && status === "active" ? (
        <Button
          size="sm"
          variant="outline"
          disabled={setStatus.pending}
          onClick={() => {
            void setStatus.run({ assetId, status: "maintenance" });
          }}
        >
          {t("Send to maintenance")}
        </Button>
      ) : null}
      {canManage && status !== "active" ? (
        <Button
          size="sm"
          variant="outline"
          disabled={setStatus.pending}
          onClick={() => {
            void setStatus.run({ assetId, status: "active" });
          }}
        >
          {t("Return to service")}
        </Button>
      ) : null}
      {canManage && status !== "retired" ? (
        <Button
          size="sm"
          variant="outline"
          disabled={setStatus.pending}
          onClick={() => {
            void setStatus.run({ assetId, status: "retired" });
          }}
        >
          {t("Retire")}
        </Button>
      ) : null}
    </>
  );
}
