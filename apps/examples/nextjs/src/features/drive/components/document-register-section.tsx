import { Frame, FrameHeader, FramePanel } from "@/components/reui/frame";
import { Skeleton } from "@/components/ui/skeleton";
import { DocumentRegister } from "@/features/drive/components/document-register";
import { getDocumentRegister } from "@/features/drive/drive-queries";

export async function DocumentRegisterSection() {
  return <DocumentRegister state={await getDocumentRegister()} />;
}

export function DocumentRegisterSectionSkeleton() {
  return (
    <Frame spacing="sm" aria-busy="true">
      <FrameHeader className="gap-1">
        <Skeleton className="h-4 w-36" />
        <Skeleton className="h-4 w-80" />
      </FrameHeader>
      <FramePanel>
        <Skeleton className="h-48" />
      </FramePanel>
    </Frame>
  );
}
