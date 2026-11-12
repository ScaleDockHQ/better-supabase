import { Skeleton } from "@/components/ui/skeleton";

/** The frame of a list while its rows load: a toolbar and `rows` grid rows. */
export function RecordListSkeleton({ rows = 6 }: { rows?: number }) {
  return (
    <div className="flex flex-col gap-4" aria-busy="true">
      <div className="flex items-center gap-2">
        <Skeleton className="h-8 w-full max-w-sm" />
        <Skeleton className="h-8 w-24" />
      </div>
      <div className="flex flex-col gap-2 rounded-xl border p-3">
        {Array.from({ length: rows }, (_, index) => (
          <Skeleton key={index} className="h-9 w-full" />
        ))}
      </div>
    </div>
  );
}
