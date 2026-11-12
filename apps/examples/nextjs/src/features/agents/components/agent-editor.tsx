"use client";

import { useAction } from "better-supabase/react";
import { useExtracted } from "next-intl";
import { useId, useState } from "react";

import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Field,
  FieldDescription,
  FieldError,
  FieldLabel,
} from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

import type { AgentDetail } from "../agents-queries";

import { updateAgent } from "../agents-actions";

const lines = (text: string): string[] =>
  text
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line !== "");

/** The configuration of one agent: instructions, model, tools and starters. */
export function AgentEditor({
  agent,
  canWrite,
}: {
  agent: AgentDetail;
  canWrite: boolean;
}) {
  const t = useExtracted("agents");
  const errorMessage = useErrorMessage();
  const fieldId = useId();
  // The editor is keyed by agent id, so each draft starts from the saved row.
  /* oxlint-disable react-doctor/no-derived-useState, react-doctor/rerender-lazy-state-init -- drafts the user edits, keyed by agent */
  const [name, setName] = useState(agent.name);
  const [description, setDescription] = useState(agent.description);
  const [instructions, setInstructions] = useState(agent.instructions);
  const [model, setModel] = useState(agent.model ?? "");
  const [tools, setTools] = useState(agent.tools.join("\n"));
  const [starters, setStarters] = useState(agent.starters.join("\n"));
  /* oxlint-enable react-doctor/no-derived-useState, react-doctor/rerender-lazy-state-init */

  const save = useAction(updateAgent, {
    onSuccess: () => {
      toast.success(t("Agent saved"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t("Configuration")}</CardTitle>
        <CardDescription>
          {t("The instructions and tools every run of this agent starts from.")}
        </CardDescription>
      </CardHeader>
      <CardContent>
        <form
          className="flex flex-col gap-4"
          onSubmit={(event) => {
            event.preventDefault();

            void save.run({
              id: agent.id,
              name,
              description,
              instructions,
              model,
              tools: lines(tools),
              starters: lines(starters),
            });
          }}
        >
          <Field>
            <FieldLabel htmlFor={`${fieldId}-name`}>{t("Name")}</FieldLabel>
            <Input
              id={`${fieldId}-name`}
              value={name}
              disabled={!canWrite}
              maxLength={80}
              required
              onChange={(event) => {
                setName(event.target.value);
              }}
            />
          </Field>
          <Field>
            <FieldLabel htmlFor={`${fieldId}-description`}>
              {t("Description")}
            </FieldLabel>
            <Input
              id={`${fieldId}-description`}
              value={description}
              disabled={!canWrite}
              maxLength={300}
              onChange={(event) => {
                setDescription(event.target.value);
              }}
            />
          </Field>
          <Field>
            <FieldLabel htmlFor={`${fieldId}-instructions`}>
              {t("Instructions")}
            </FieldLabel>
            <Textarea
              id={`${fieldId}-instructions`}
              value={instructions}
              disabled={!canWrite}
              rows={8}
              required
              onChange={(event) => {
                setInstructions(event.target.value);
              }}
            />
          </Field>
          <Field>
            <FieldLabel htmlFor={`${fieldId}-model`}>{t("Model")}</FieldLabel>
            <Input
              id={`${fieldId}-model`}
              value={model}
              disabled={!canWrite}
              placeholder="openai/gpt-5-mini"
              onChange={(event) => {
                setModel(event.target.value);
              }}
            />
            <FieldDescription>
              {t(
                "An AI Gateway provider/model string. Empty uses the app default.",
              )}
            </FieldDescription>
          </Field>
          <Field>
            <FieldLabel htmlFor={`${fieldId}-tools`}>{t("Tools")}</FieldLabel>
            <Textarea
              id={`${fieldId}-tools`}
              value={tools}
              disabled={!canWrite}
              rows={3}
              onChange={(event) => {
                setTools(event.target.value);
              }}
            />
            <FieldDescription>{t("One tool name per line.")}</FieldDescription>
          </Field>
          <Field>
            <FieldLabel htmlFor={`${fieldId}-starters`}>
              {t("Starters")}
            </FieldLabel>
            <Textarea
              id={`${fieldId}-starters`}
              value={starters}
              disabled={!canWrite}
              rows={3}
              onChange={(event) => {
                setStarters(event.target.value);
              }}
            />
            <FieldDescription>
              {t(
                "Prompts the chat offers before the first message, one per line.",
              )}
            </FieldDescription>
            {save.error === undefined ? null : (
              <FieldError>{errorMessage(save.error)}</FieldError>
            )}
          </Field>
          {canWrite ? (
            <div className="flex justify-end">
              <Button type="submit" disabled={save.pending}>
                {t("Save agent")}
              </Button>
            </div>
          ) : null}
        </form>
      </CardContent>
    </Card>
  );
}
