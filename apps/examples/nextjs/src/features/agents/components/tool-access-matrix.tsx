"use client";

import { useAction } from "better-supabase/react";
import { useExtracted } from "next-intl";
import { useState } from "react";

import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

import type { ToolAccessRow } from "../agents-queries";
import type { ToolPolicyChoice } from "../agents-tools";

import { saveToolPolicies } from "../agents-actions";

/** `default` removes the saved rule. */
type Choice = ToolPolicyChoice | "default";

const choiceOf = (policy: ToolPolicyChoice | undefined): Choice =>
  policy ?? "default";

/**
 * The tool access matrix: one row per tool with the rule for the organization.
 * A change waits in a save bar until the admin saves, then each changed rule is
 * written in one action.
 */
export function ToolAccessMatrix({
  rows,
  canManage,
}: {
  rows: readonly ToolAccessRow[];
  canManage: boolean;
}) {
  const t = useExtracted("agents");
  const errorMessage = useErrorMessage();
  const [draft, setDraft] = useState<Readonly<Record<string, Choice>>>({});

  const save = useAction(saveToolPolicies, {
    onSuccess: (count) => {
      setDraft({});
      toast.success(t("Saved {count, number} rules", { count }));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  const changes = rows.flatMap((row) => {
    const choice = draft[row.tool];

    return choice === undefined || choice === choiceOf(row.policy)
      ? []
      : [{ tool: row.tool, policy: choice === "default" ? null : choice }];
  });

  const options: readonly { value: Choice; label: string }[] = [
    { value: "default", label: t("Default") },
    { value: "auto", label: t("Run") },
    { value: "ask", label: t("Ask") },
    { value: "deny", label: t("Deny") },
  ];

  return (
    <div className="flex flex-col gap-3">
      <ul className="divide-y rounded-xl border">
        {rows.map((row) => (
          <li
            key={row.tool}
            className="flex flex-wrap items-center gap-3 px-4 py-3 text-sm"
          >
            <div className="flex min-w-0 flex-1 flex-col gap-1">
              <span className="font-medium">{row.tool}</span>
              <span className="flex flex-wrap gap-1">
                {row.agents.length === 0 ? (
                  <span className="text-xs text-muted-foreground">
                    {t("Built in")}
                  </span>
                ) : (
                  row.agents.map((agent) => (
                    <Badge key={agent} variant="secondary">
                      {agent}
                    </Badge>
                  ))
                )}
              </span>
            </div>
            <ToggleGroup
              variant="outline"
              size="sm"
              spacing={0}
              disabled={!canManage}
              value={[draft[row.tool] ?? choiceOf(row.policy)]}
              aria-label={t("Rule for {tool}", { tool: row.tool })}
              onValueChange={(values) => {
                const next = values[0];

                if (
                  next === "default" ||
                  next === "auto" ||
                  next === "ask" ||
                  next === "deny"
                ) {
                  setDraft((current) => ({ ...current, [row.tool]: next }));
                }
              }}
            >
              {options.map((option) => (
                <ToggleGroupItem key={option.value} value={option.value}>
                  {option.label}
                </ToggleGroupItem>
              ))}
            </ToggleGroup>
          </li>
        ))}
      </ul>
      {changes.length === 0 ? null : (
        <section
          className="sticky bottom-4 flex items-center gap-2 rounded-lg border bg-card px-4 py-3 text-sm"
          aria-label={t("Unsaved changes")}
        >
          <span className="mr-auto tabular-nums">
            {t("{count, number} unsaved changes", { count: changes.length })}
          </span>
          <Button
            size="sm"
            variant="ghost"
            onClick={() => {
              setDraft({});
            }}
          >
            {t("Discard")}
          </Button>
          <Button
            size="sm"
            disabled={save.pending}
            onClick={() => {
              void save.run({ policies: changes });
            }}
          >
            {t("Save rules")}
          </Button>
        </section>
      )}
    </div>
  );
}
