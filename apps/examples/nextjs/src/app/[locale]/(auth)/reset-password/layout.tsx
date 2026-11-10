import type { ReactNode } from "react";

import { RouteMessages } from "@/i18n/route-messages";

export default function ResetPasswordLayout({
  children,
}: {
  children: ReactNode;
}) {
  return (
    <RouteMessages namespaces={["auth", "offline"]}>{children}</RouteMessages>
  );
}
