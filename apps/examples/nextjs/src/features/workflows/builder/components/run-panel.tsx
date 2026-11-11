"use client";

import type { WorkflowRun } from "better-supabase/blocks/workflows";

import { ExternalLinkIcon, FlaskConicalIcon, PlayIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import { Field, FieldDescription, FieldLabel } from "@/components/ui/field";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { Link } from "@/i18n/navigation";

import { statusBadge } from "../../workflow-labels";

/**
 * Test and live runs from the editor. A test run takes the stubs below instead
 * of calling steps, and its node states show on the canvas; pick any past run
 * to overlay it.
 */
export function RunPanel({
  input,
  stubs,
  published,
  pending,
  options,
  runId,
  run,
  onInput,
  onStubs,
  onRun,
  onTest,
  onPick,
}: {
  input: string;
  stubs: string;
  /** A published version exists, which a live run needs. */
  published: boolean;
  pending: boolean;
  /**
   * Runs to pick from: live runs of the definition and this session's test
   * runs.
   */
  options: readonly { readonly value: string; readonly label: string }[];
  runId: string | null;
  /** The run on the overlay, once it loaded. */
  run: WorkflowRun | undefined;
  onInput: (value: string) => void;
  onStubs: (value: string) => void;
  onRun: () => void;
  onTest: () => void;
  onPick: (externalId: string) => void;
}) {
  const t = useExtracted("workflows");

  return (
    <div className="flex flex-col gap-4">
      <Field>
        <FieldLabel htmlFor="run-input">{t("Run input")}</FieldLabel>
        <Textarea
          id="run-input"
          value={input}
          rows={3}
          className="font-mono text-xs"
          placeholder={t("Text, or a JSON object such as {example}", {
            example: '{"items": ["a"]}',
          })}
          onChange={(event) => {
            onInput(event.target.value);
          }}
        />
        <FieldDescription>
          {t("Text becomes input.text; a JSON object becomes the input.")}
        </FieldDescription>
      </Field>
      <Field>
        <FieldLabel htmlFor="run-stubs">{t("Test stubs (JSON)")}</FieldLabel>
        <Textarea
          id="run-stubs"
          value={stubs}
          rows={3}
          className="font-mono text-xs"
          placeholder='{"node-id": {"text": "output"}}'
          onChange={(event) => {
            onStubs(event.target.value);
          }}
        />
        <FieldDescription>
          {t(
            "What each node returns in a test run, by node id. Approvals take {example} to test the other branch.",
            { example: '{"approved": false}' },
          )}
        </FieldDescription>
      </Field>
      <div className="flex flex-wrap gap-2">
        <Button size="sm" variant="outline" disabled={pending} onClick={onTest}>
          <FlaskConicalIcon />
          {t("Test run")}
        </Button>
        <Button size="sm" disabled={pending || !published} onClick={onRun}>
          <PlayIcon />
          {t("Run")}
        </Button>
      </div>
      <Field>
        <FieldLabel htmlFor="run-pick">
          {t("Show a run on the canvas")}
        </FieldLabel>
        <Select
          value={runId}
          onValueChange={(value) => {
            if (value !== null) {
              onPick(value);
            }
          }}
          items={options}
        >
          <SelectTrigger id="run-pick">
            <SelectValue placeholder={t("No run shown")} />
          </SelectTrigger>
          <SelectContent>
            {options.map((item) => (
              <SelectItem key={item.value} value={item.value}>
                {item.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </Field>
      {run === undefined ? null : (
        <div className="flex items-center gap-2 text-sm">
          <Badge variant={statusBadge(run.status)}>{run.status}</Badge>
          <Link
            href={`/workflows/runs/${run.id}`}
            className="inline-flex items-center gap-1 text-primary hover:underline"
          >
            {t("Open the run")}
            <ExternalLinkIcon className="size-3" />
          </Link>
        </div>
      )}
    </div>
  );
}
