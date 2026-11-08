import type { ReactNode } from "react";
import type { ExternalToast } from "sonner";

type Message = (() => ReactNode) | ReactNode;

async function show(
  name: Kind,
  message: Message,
  data?: ExternalToast,
): Promise<void> {
  // Sonner loads on the first toast, so a route ships it only once a toast is
  // raised; the `Toaster` that renders it loads after the first paint.
  const { toast } = await import("sonner");

  toast[name](message, data);
}

type Kind = "error" | "message" | "success" | "warning";

const kind =
  (name: Kind) =>
  (message: Message, data?: ExternalToast): void => {
    void show(name, message, data);
  };

/**
 * `toast` from sonner behind a dynamic import. The calls return nothing: no
 * caller reads a toast id.
 */
export const toast = {
  error: kind("error"),
  message: kind("message"),
  success: kind("success"),
  warning: kind("warning"),
};
