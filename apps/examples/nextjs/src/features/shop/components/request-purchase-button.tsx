"use client";

import { useAction } from "better-supabase/react";
import { ShoppingCartIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { useErrorMessage } from "@/lib/use-error-message";

import { requestPurchase } from "../shop-actions";

interface RequestPurchaseButtonProps {
  readonly variantId: string;
  readonly locationId: string;
  /** Base units to ask for. */
  readonly quantity: number;
  /** Names the product and location for screen readers. */
  readonly label: string;
}

export function RequestPurchaseButton({
  variantId,
  locationId,
  quantity,
  label,
}: RequestPurchaseButtonProps) {
  const t = useExtracted("shop");
  const errorMessage = useErrorMessage();

  const request = useAction(requestPurchase, {
    onSuccess: () => {
      toast.success(t("Purchase requested"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <Button
      size="sm"
      variant="outline"
      disabled={request.pending}
      aria-label={t("Request {quantity} of {label}", {
        quantity: String(quantity),
        label,
      })}
      onClick={() => {
        void request.run({ variantId, locationId, quantity });
      }}
    >
      <ShoppingCartIcon />
      {t("Request purchase")}
    </Button>
  );
}
