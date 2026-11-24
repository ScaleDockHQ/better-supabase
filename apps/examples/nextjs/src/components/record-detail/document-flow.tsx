import { CheckIcon } from "lucide-react";

import { Badge } from "@/components/reui/badge";
import { Link, toAppHref } from "@/i18n/navigation";

export interface DocumentFlowStep {
  readonly label: string;
  readonly state: "done" | "current" | "todo";
  readonly href?: string | undefined;
  readonly detail?: string | undefined;
}

/**
 * The documents of a chain (quote, order, payment, shipment) as one strip. Each
 * step says whether it is done; a step with an `href` links to its record.
 */
export function DocumentFlow({
  label,
  steps,
}: {
  label: string;
  steps: readonly DocumentFlowStep[];
}) {
  return (
    <nav aria-label={label}>
      <ol className="flex flex-wrap items-center gap-2 text-sm">
        {steps.map((step, index) => (
          <li key={step.label} className="flex items-center gap-2">
            {index > 0 ? (
              <span aria-hidden className="text-muted-foreground">
                /
              </span>
            ) : null}
            <Badge
              variant={
                step.state === "done"
                  ? "success-light"
                  : step.state === "current"
                    ? "primary-light"
                    : "secondary"
              }
            >
              {step.state === "done" ? <CheckIcon /> : null}
              {step.href ? (
                <Link href={toAppHref(step.href)}>{step.label}</Link>
              ) : (
                step.label
              )}
            </Badge>
            {step.detail ? (
              <span className="text-xs text-muted-foreground">
                {step.detail}
              </span>
            ) : null}
          </li>
        ))}
      </ol>
    </nav>
  );
}
