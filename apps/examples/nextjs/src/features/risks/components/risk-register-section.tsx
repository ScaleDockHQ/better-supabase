import { RiskRegister } from "@/features/risks/components/risk-register";
import { getRiskRegister } from "@/features/risks/risks-queries";

// skeleton: the page passes the wrapped component's own skeleton to <Suspense>
export async function RiskRegisterSection() {
  return <RiskRegister state={await getRiskRegister()} />;
}
