import type { ReactNode } from "react";

import { FinanceMessages } from "@/features/finance-records/components/finance-messages";

export default function BankingLayout({ children }: { children: ReactNode }) {
  return <FinanceMessages also={["banking"]}>{children}</FinanceMessages>;
}
