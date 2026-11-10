import { TriangleAlertIcon } from "lucide-react";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";

/**
 * What the search and the filters show while the prerendered list loads, or
 * when it failed: tiles of the real height, or an alert with Retry.
 */
export function IndexPending({
  failed,
  onRetry,
}: {
  failed: boolean;
  onRetry: () => void;
}) {
  if (failed) {
    return (
      <Alert variant="destructive">
        <TriangleAlertIcon aria-hidden="true" />
        <AlertTitle>The list did not load</AlertTitle>
        <AlertDescription>
          Check your connection and try again. The categories below still list
          every block.
        </AlertDescription>
        <AlertAction>
          <Button variant="outline" size="sm" onClick={onRetry}>
            Retry
          </Button>
        </AlertAction>
      </Alert>
    );
  }

  return (
    <ul
      aria-busy="true"
      aria-label="Loading"
      className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-3"
    >
      {Array.from({ length: 6 }, (_, index) => (
        <li key={index}>
          <Skeleton className="h-28 w-full" />
        </li>
      ))}
    </ul>
  );
}
