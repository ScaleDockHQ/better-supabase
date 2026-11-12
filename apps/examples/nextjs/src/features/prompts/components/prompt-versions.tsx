"use client";

import { useAction } from "better-supabase/react";
import { useExtracted, useFormatter } from "next-intl";

import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

import type { PromptVersionRow } from "../prompts-queries";

import { setPromptLabel } from "../prompts-actions";

/**
 * The versions of a prompt with their labels, and the buttons that move a
 * label.
 */
export function PromptVersions({
  name,
  versions,
}: {
  name: string;
  versions: readonly PromptVersionRow[];
}) {
  const t = useExtracted("prompts");
  const format = useFormatter();
  const errorMessage = useErrorMessage();

  const label = useAction(setPromptLabel, {
    onSuccess: (version) => {
      toast.success(t("Label moved to version {version, number}", { version }));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <Card size="sm">
      <CardHeader>
        <CardTitle>{t("Versions")}</CardTitle>
        <CardDescription>
          {t(
            "Promote a version, or roll back by moving the label to an older one.",
          )}
        </CardDescription>
      </CardHeader>
      <CardContent>
        {versions.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            {t("Nothing saved yet. The assistant uses its built-in text.")}
          </p>
        ) : (
          <ol className="flex flex-col gap-3">
            {versions.map((entry) => (
              <li key={entry.version} className="flex flex-col gap-1 text-sm">
                <p className="flex flex-wrap items-center gap-1">
                  <span className="font-medium tabular-nums">
                    v{entry.version}
                  </span>
                  {entry.labels.map((value) => (
                    <Badge
                      key={value}
                      variant={
                        value === "production" ? "success-light" : "info-light"
                      }
                    >
                      {value}
                    </Badge>
                  ))}
                  <span className="ml-auto text-xs text-muted-foreground tabular-nums">
                    {entry.createdAt === undefined
                      ? ""
                      : format.dateTime(new Date(entry.createdAt), {
                          dateStyle: "medium",
                        })}
                  </span>
                </p>
                <p className="line-clamp-2 text-xs text-muted-foreground">
                  {entry.template}
                </p>
                <div className="flex gap-1">
                  {(["production", "staging"] as const).map((value) =>
                    entry.labels.includes(value) ? null : (
                      <Button
                        key={value}
                        size="xs"
                        variant="outline"
                        disabled={label.pending}
                        onClick={() => {
                          void label.run({
                            name,
                            label: value,
                            version: entry.version,
                          });
                        }}
                      >
                        {value === "production" ? t("Make live") : t("Stage")}
                      </Button>
                    ),
                  )}
                </div>
              </li>
            ))}
          </ol>
        )}
      </CardContent>
    </Card>
  );
}
