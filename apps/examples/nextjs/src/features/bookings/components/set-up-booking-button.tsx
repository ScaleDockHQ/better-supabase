"use client";

import { useAction } from "better-supabase/react";
import { PlusIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { useErrorMessage } from "@/lib/use-error-message";

import { setUpBookingPage } from "../bookings-actions";

/** Sets up the booking page in the zone of the browser that clicks it. */
export function SetUpBookingButton() {
  const t = useExtracted("bookings");
  const errorMessage = useErrorMessage();

  const setUp = useAction(setUpBookingPage, {
    onSuccess: () => {
      toast.success(t("Booking page ready"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <Button
      disabled={setUp.pending}
      onClick={() =>
        void setUp.run({ tz: Intl.DateTimeFormat().resolvedOptions().timeZone })
      }
    >
      <PlusIcon />
      {t("Set up booking page")}
    </Button>
  );
}
