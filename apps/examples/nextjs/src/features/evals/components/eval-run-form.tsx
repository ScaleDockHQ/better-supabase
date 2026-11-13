"use client";

import { useAction, useErrorMessage } from "better-supabase/react";
import { PlayIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useRouter } from "next/navigation";
import { useState } from "react";

import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { toast } from "@/lib/toast";

import { startEvalRun } from "../evals-actions";

const MODELS = [
  "openai/gpt-5-mini",
  "anthropic/claude-sonnet-4.5",
  "google/gemini-2.5-flash",
];

/** Picks a prompt version and a model, then starts a run of the dataset. */
export function EvalRunForm({
  name,
  versions,
  items,
}: {
  name: string;
  versions: readonly number[];
  items: number;
}) {
  const t = useExtracted("evals");
  const router = useRouter();
  const errorMessage = useErrorMessage();
  const [version, setVersion] = useState(String(versions[0] ?? 1));
  const [model, setModel] = useState(MODELS[0] ?? "");

  const start = useAction(startEvalRun, {
    onSuccess: (runId) => {
      toast.success(t("Run started"));
      router.push(`/assistant/evals/${encodeURIComponent(name)}?run=${runId}`);
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  const versionItems = versions.map((entry) => ({
    value: String(entry),
    label: t("Version {version, number}", { version: entry }),
  }));

  const modelItems = MODELS.map((entry) => ({ value: entry, label: entry }));

  return (
    <div className="flex flex-wrap items-center gap-2">
      <Select
        value={version}
        items={versionItems}
        disabled={versionItems.length === 0}
        onValueChange={(value) => {
          if (value !== null) {
            setVersion(value);
          }
        }}
      >
        <SelectTrigger
          size="sm"
          className="w-36"
          aria-label={t("Prompt version")}
        >
          <SelectValue placeholder={t("No versions")} />
        </SelectTrigger>
        <SelectContent>
          {versionItems.map((item) => (
            <SelectItem key={item.value} value={item.value}>
              {item.label}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
      <Select
        value={model}
        items={modelItems}
        onValueChange={(value) => {
          if (value !== null) {
            setModel(value);
          }
        }}
      >
        <SelectTrigger size="sm" className="w-56" aria-label={t("Model")}>
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          {modelItems.map((item) => (
            <SelectItem key={item.value} value={item.value}>
              {item.label}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
      <Button
        size="sm"
        disabled={start.pending || versions.length === 0 || items === 0}
        onClick={() => {
          void start.run({ name, promptVersion: Number(version), model });
        }}
      >
        <PlayIcon />
        {t("Run {count, number} items", { count: items })}
      </Button>
    </div>
  );
}
