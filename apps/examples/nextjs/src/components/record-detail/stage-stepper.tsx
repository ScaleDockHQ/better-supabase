import { ChevronRightIcon } from "lucide-react";

import { Badge } from "@/components/reui/badge";

export interface Stage {
  readonly id: string;
  readonly name: string;
}

/**
 * The stage path of a record: done stages, the current one and the stages to
 * come. It renders from the stages the page already loaded and takes no
 * actions; put the move buttons beside it.
 */
export function StageStepper({
  stages,
  currentId,
  label,
}: {
  stages: readonly Stage[];
  currentId: string | null;
  /** The accessible name of the list, such as "Deal stage". */
  label: string;
}) {
  const current = stages.findIndex((stage) => stage.id === currentId);

  return (
    <ol aria-label={label} className="flex flex-wrap items-center gap-2">
      {stages.map((stage, index) => (
        <li key={stage.id} className="flex items-center gap-2">
          {index > 0 ? (
            <ChevronRightIcon className="size-4 text-muted-foreground" />
          ) : null}
          <Badge
            variant={
              index === current
                ? "primary-light"
                : index < current
                  ? "secondary"
                  : "outline"
            }
            aria-current={index === current ? "step" : undefined}
          >
            {stage.name}
          </Badge>
        </li>
      ))}
    </ol>
  );
}
