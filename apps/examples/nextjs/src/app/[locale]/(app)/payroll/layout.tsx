import type { ReactNode } from "react";

import { FinanceMessages } from "@/features/finance-records/components/finance-messages";

export default function Layout({ children }: { children: ReactNode }) {
  return <FinanceMessages>{children}</FinanceMessages>;
}
