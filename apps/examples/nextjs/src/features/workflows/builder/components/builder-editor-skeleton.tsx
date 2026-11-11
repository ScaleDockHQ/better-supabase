import { Skeleton } from "@/components/ui/skeleton";

/** The editor's frame while the canvas loads: toolbar, palette, canvas, panel. */
export function BuilderEditorSkeleton() {
  return (
    <div className="flex flex-col gap-3" aria-busy="true">
      <Skeleton className="h-8 w-full" />
      <div className="flex gap-3">
        <Skeleton className="h-150 w-56 shrink-0" />
        <Skeleton className="h-150 flex-1" />
        <Skeleton className="h-150 w-80 shrink-0" />
      </div>
    </div>
  );
}
