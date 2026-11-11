import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";

/** A section card while its rows load. */
export function RecordSectionSkeleton({ rows = 2 }: { rows?: number }) {
  return (
    <Card size="sm" aria-busy="true">
      <CardHeader>
        <Skeleton className="h-5 w-28" />
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        {Array.from({ length: rows }, (_, index) => (
          <Skeleton key={index} className="h-10" />
        ))}
      </CardContent>
    </Card>
  );
}
