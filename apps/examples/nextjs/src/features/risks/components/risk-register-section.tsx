import { Frame, FrameHeader, FramePanel } from "@/components/reui/frame";
import { Skeleton } from "@/components/ui/skeleton";
import { RiskRegister } from "@/features/risks/components/risk-register";
import { getRiskRegister } from "@/features/risks/risks-queries";

export async function RiskRegisterSection() {
  return <RiskRegister state={await getRiskRegister()} />;
}

export function RiskRegisterSectionSkeleton() {
  return (
    <Frame spacing="sm" aria-busy="true">
      <FrameHeader className="gap-1">
        <Skeleton className="h-4 w-28" />
        <Skeleton className="h-4 w-80" />
      </FrameHeader>
      <FramePanel>
        <Skeleton className="h-48" />
      </FramePanel>
    </Frame>
  );
}
