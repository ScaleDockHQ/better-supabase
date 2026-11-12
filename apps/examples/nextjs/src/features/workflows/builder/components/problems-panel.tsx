"use client";

import {
  CircleCheckIcon,
  CircleAlertIcon,
  TriangleAlertIcon,
} from "lucide-react";
import { useExtracted } from "next-intl";

import { Alert, AlertDescription, AlertTitle } from "@/components/reui/alert";
import { Button } from "@/components/ui/button";

import type { EditorIssue } from "../editor-model";

/** The validation panel: what blocks publishing and what only looks wrong. */
export function ProblemsPanel({
  issues,
  onSelect,
}: {
  issues: readonly EditorIssue[];
  /** Selects the node an issue is about on the canvas. */
  onSelect: (node: string) => void;
}) {
  const t = useExtracted("workflows");

  if (issues.length === 0) {
    return (
      <Alert variant="success" data-testid="no-problems">
        <CircleCheckIcon />
        <AlertTitle>{t("No problems")}</AlertTitle>
        <AlertDescription>
          {t("The graph is ready to publish.")}
        </AlertDescription>
      </Alert>
    );
  }

  return (
    <ul className="flex flex-col gap-2" data-testid="problems">
      {issues.map((issue) => {
        const Icon =
          issue.severity === "error" ? CircleAlertIcon : TriangleAlertIcon;

        const { node } = issue;

        return (
          <li key={`${issue.severity}:${issue.node ?? ""}:${issue.message}`}>
            <Alert
              variant={issue.severity === "error" ? "destructive" : "warning"}
            >
              <Icon />
              <AlertTitle>
                {issue.severity === "error" ? t("Error") : t("Warning")}
              </AlertTitle>
              <AlertDescription>
                {issue.message}
                {node === undefined ? null : (
                  <Button
                    variant="link"
                    size="xs"
                    className="ml-1"
                    onClick={() => {
                      onSelect(node);
                    }}
                  >
                    {t("Show node")}
                  </Button>
                )}
              </AlertDescription>
            </Alert>
          </li>
        );
      })}
    </ul>
  );
}
