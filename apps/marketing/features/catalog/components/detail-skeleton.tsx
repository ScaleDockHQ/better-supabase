import { Skeleton } from "@/components/ui/skeleton";

/**
 * The block and recipe pages' fallback while their URL data streams in after
 * a navigation. It keeps the header, hero and first section in place.
 */
export function DetailSkeleton() {
  return (
    <div
      aria-busy="true"
      className="flex flex-col gap-10 motion-reduce:*:animate-none"
    >
      <span className="sr-only">Loading</span>
      <div className="flex flex-col gap-6">
        <Skeleton className="h-4 w-48" />
        <div className="flex items-center gap-3">
          <Skeleton className="size-10" />
          <div className="flex flex-col gap-2">
            <Skeleton className="h-7 w-56" />
            <Skeleton className="h-3 w-24" />
          </div>
        </div>
        <div className="flex max-w-2xl flex-col gap-2">
          <Skeleton className="h-4 w-full" />
          <Skeleton className="h-4 w-5/6" />
        </div>
        <Skeleton className="aspect-[21/9] w-full" />
      </div>
      <div className="flex flex-col gap-3">
        <Skeleton className="h-6 w-32" />
        <Skeleton className="h-24 w-full" />
      </div>
    </div>
  );
}
