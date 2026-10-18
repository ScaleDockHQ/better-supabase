"use client";

import type { DbError } from "better-supabase";
import type {
  FulfillmentStatus,
  OrderStatus,
} from "better-supabase/blocks/orders";

import { useAction } from "better-supabase/react";
import { useExtracted } from "next-intl";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { useRouter } from "@/i18n/navigation";
import { useErrorMessage } from "@/lib/use-error-message";

import {
  cancelOrder,
  deliverFulfillment,
  fulfillOrder,
  markOrderPaid,
  placeOrder,
  shipFulfillment,
} from "../shop-actions";

function useToastError(): (error: DbError) => void {
  const errorMessage = useErrorMessage();

  return (error) => {
    toast.error(errorMessage(error));
  };
}

/** Places the draft and opens the new order. */
export function PlaceOrderButton({
  cartId,
  disabled,
}: {
  cartId: string;
  disabled: boolean;
}) {
  const t = useExtracted("shop");
  const router = useRouter();
  const onError = useToastError();

  const place = useAction(placeOrder, {
    onSuccess: (orderId) => {
      toast.success(t("Order placed"));
      router.replace(`/shop/orders/${orderId}`);
    },
    onError,
  });

  return (
    <Button
      disabled={disabled || place.pending}
      onClick={() => {
        void place.run({ cartId });
      }}
    >
      {t("Place order")}
    </Button>
  );
}

/** The next steps a placed order can take, as buttons. */
export function OrderTransitions({
  orderId,
  status,
  fulfillments,
}: {
  orderId: string;
  status: OrderStatus;
  fulfillments: readonly {
    readonly id: string;
    readonly status: FulfillmentStatus;
  }[];
}) {
  const t = useExtracted("shop");
  const onError = useToastError();

  const done = (message: string) => () => {
    toast.success(message);
  };

  const pay = useAction(markOrderPaid, {
    onSuccess: done(t("Payment recorded")),
    onError,
  });

  const cancel = useAction(cancelOrder, {
    onSuccess: done(t("Order cancelled")),
    onError,
  });

  const fulfill = useAction(fulfillOrder, {
    onSuccess: done(t("Fulfillment created")),
    onError,
  });

  const ship = useAction(shipFulfillment, {
    onSuccess: done(t("Marked as shipped")),
    onError,
  });

  const deliver = useAction(deliverFulfillment, {
    onSuccess: done(t("Marked as delivered")),
    onError,
  });

  const pending =
    pay.pending ||
    cancel.pending ||
    fulfill.pending ||
    ship.pending ||
    deliver.pending;

  const toShip = fulfillments.find((each) => each.status === "pending");
  const toDeliver = fulfillments.find((each) => each.status === "shipped");

  switch (status) {
    case "pending_payment": {
      return (
        <div className="flex flex-wrap gap-2">
          <Button
            disabled={pending}
            onClick={() => {
              void pay.run({ orderId });
            }}
          >
            {t("Mark as paid")}
          </Button>
          <Button
            variant="outline"
            disabled={pending}
            onClick={() => {
              void cancel.run({ orderId });
            }}
          >
            {t("Cancel order")}
          </Button>
        </div>
      );
    }

    case "paid":
    case "fulfilled": {
      return (
        <div className="flex flex-wrap gap-2">
          {status === "paid" && !toShip && !toDeliver ? (
            <Button
              disabled={pending}
              onClick={() => {
                void fulfill.run({ orderId });
              }}
            >
              {t("Create fulfillment")}
            </Button>
          ) : null}
          {toShip ? (
            <Button
              disabled={pending}
              onClick={() => {
                void ship.run({ fulfillmentId: toShip.id });
              }}
            >
              {t("Mark as shipped")}
            </Button>
          ) : null}
          {toDeliver ? (
            <Button
              variant={toShip ? "outline" : "default"}
              disabled={pending}
              onClick={() => {
                void deliver.run({ fulfillmentId: toDeliver.id });
              }}
            >
              {t("Mark as delivered")}
            </Button>
          ) : null}
        </div>
      );
    }

    case "completed":
    case "cancelled":
    case "refunded": {
      return (
        <p className="text-sm text-muted-foreground">
          {t("Nothing left to do for this order.")}
        </p>
      );
    }

    default: {
      const unknown: never = status;

      return unknown;
    }
  }
}
