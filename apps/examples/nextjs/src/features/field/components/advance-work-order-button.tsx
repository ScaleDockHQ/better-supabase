"use client";

import { useAction } from "better-supabase/react";
import { CircleCheckIcon, MapPinIcon, NavigationIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { useErrorMessage } from "@/lib/use-error-message";

import { advanceWorkOrder } from "../field-actions";

/** The next step of a stop: leave for it, arrive, then finish. */
export function AdvanceWorkOrderButton({
  id,
  to,
}: {
  id: string;
  to: "en_route" | "on_site" | "done";
}) {
  const t = useExtracted("field");
  const errorMessage = useErrorMessage();

  const advance = useAction(advanceWorkOrder, {
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  const run = () => void advance.run({ id, to });

  switch (to) {
    case "en_route": {
      return (
        <Button size="sm" disabled={advance.pending} onClick={run}>
          <NavigationIcon />
          {t("Leave for the stop")}
        </Button>
      );
    }

    case "on_site": {
      return (
        <Button size="sm" disabled={advance.pending} onClick={run}>
          <MapPinIcon />
          {t("Arrived")}
        </Button>
      );
    }

    case "done": {
      return (
        <Button size="sm" disabled={advance.pending} onClick={run}>
          <CircleCheckIcon />
          {t("Mark done")}
        </Button>
      );
    }

    default: {
      const unhandled: never = to;

      return unhandled;
    }
  }
}
