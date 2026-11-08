import type { ReactNode } from "react";
import type { ExternalToast } from "sonner";

type Message = (() => ReactNode) | ReactNode;

async function show(
  kind: "error" | "success" | "warning",
  message: Message,
  data?: ExternalToast,
): Promise<void> {
  // Sonner loads on the first toast, so a route ships it only once a toast is
  // raised; the `Toaster` that renders it loads after the first paint.
  const { toast } = await import("sonner");

  toast[kind](message, data);
}

/**
 * `toast` from sonner behind a dynamic import. The calls return nothing: no
 * caller reads a toast id.
 */
export const toast = {
  error: (message: Message, data?: ExternalToast): void => {
    void show("error", message, data);
  },
  success: (message: Message, data?: ExternalToast): void => {
    void show("success", message, data);
  },
  warning: (message: Message, data?: ExternalToast): void => {
    void show("warning", message, data);
  },
};
