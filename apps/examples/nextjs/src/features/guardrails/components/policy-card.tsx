"use client";

import type { PiiKind } from "better-supabase/blocks/ai-guardrails";

import { PII_KINDS } from "better-supabase/blocks/ai-guardrails";
import { useAction } from "better-supabase/react";
import { useExtracted } from "next-intl";
import { useId, useState } from "react";

import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Field, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

import type { PolicyCard as Policy } from "../guardrails-queries";

import { savePolicy } from "../guardrails-actions";

const NONE = "none";

/** A short sentence per check the policy turns on. */
function Summary({ policy }: { policy: Policy }) {
  const t = useExtracted("guardrails");
  const config = policy.config;

  if (config === undefined || !policy.enabled) {
    return (
      <p className="text-sm text-muted-foreground">{t("No checks run.")}</p>
    );
  }

  return (
    <ul className="flex flex-wrap gap-1">
      {config.injection === undefined ? null : (
        <li>
          <Badge variant="warning-light">
            {t("Injection: {action}", { action: config.injection.action })}
          </Badge>
        </li>
      )}
      {config.pii === undefined ? null : (
        <li>
          <Badge variant="warning-light">
            {t("PII: {action}", { action: config.pii.action })}
          </Badge>
        </li>
      )}
      {config.denyTopics === undefined ? null : (
        <li>
          <Badge variant="warning-light">
            {t("{count, number} denied topics", {
              count: config.denyTopics.length,
            })}
          </Badge>
        </li>
      )}
      {config.maxToolDepth === undefined ? null : (
        <li>
          <Badge variant="warning-light">
            {t("Tool depth {depth, number}", { depth: config.maxToolDepth })}
          </Badge>
        </li>
      )}
    </ul>
  );
}

/** Two steps: pick the checks, then review and save. */
function PolicyWizard({ policy }: { policy: Policy }) {
  const t = useExtracted("guardrails");
  const errorMessage = useErrorMessage();
  const fieldId = useId();
  const config = policy.config;
  const [open, setOpen] = useState(false);
  const [step, setStep] = useState(1);

  const [injection, setInjection] = useState<string>(
    config?.injection?.action ?? NONE,
  );

  const [pii, setPii] = useState<string>(config?.pii?.action ?? NONE);

  const [kinds, setKinds] = useState<readonly PiiKind[]>(
    () => config?.pii?.kinds ?? PII_KINDS,
  );

  const [topics, setTopics] = useState(() =>
    (config?.denyTopics ?? [])
      .map((topic) => (typeof topic === "string" ? topic : topic.topic))
      .join(", "),
  );

  const [depth, setDepth] = useState(String(config?.maxToolDepth ?? ""));

  const save = useAction(savePolicy, {
    onSuccess: () => {
      toast.success(t("Policy saved"));
      setOpen(false);
      setStep(1);
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  const actionItems = (values: readonly string[]) => [
    { value: NONE, label: t("Off") },
    ...values.map((value) => ({ value, label: value })),
  ];

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger render={<Button size="sm" variant="outline" />}>
        {t("Edit policy")}
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>
            {t("{agent} {stage} policy", {
              agent: policy.title,
              stage: policy.stage,
            })}
          </DialogTitle>
          <DialogDescription>
            {step === 1
              ? t("Step 1 of 2: choose the checks.")
              : t(
                  "Step 2 of 2: review and save. The policy applies to the next request.",
                )}
          </DialogDescription>
        </DialogHeader>
        {step === 1 ? (
          <div className="flex flex-col gap-4">
            <Field>
              <FieldLabel>{t("Prompt injection")}</FieldLabel>
              <Select
                value={injection}
                items={actionItems(["block", "flag"])}
                onValueChange={(value) => {
                  if (value !== null) {
                    setInjection(value);
                  }
                }}
              >
                <SelectTrigger size="sm" aria-label={t("Prompt injection")}>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {actionItems(["block", "flag"]).map((item) => (
                    <SelectItem key={item.value} value={item.value}>
                      {item.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
            <Field>
              <FieldLabel>{t("Personal data")}</FieldLabel>
              <Select
                value={pii}
                items={actionItems(["block", "redact", "flag"])}
                onValueChange={(value) => {
                  if (value !== null) {
                    setPii(value);
                  }
                }}
              >
                <SelectTrigger size="sm" aria-label={t("Personal data")}>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {actionItems(["block", "redact", "flag"]).map((item) => (
                    <SelectItem key={item.value} value={item.value}>
                      {item.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {pii === NONE ? null : (
                <ul className="flex flex-wrap gap-3 pt-1">
                  {PII_KINDS.map((kind) => (
                    <li key={kind}>
                      <label className="flex items-center gap-1.5 text-sm">
                        <Checkbox
                          checked={kinds.includes(kind)}
                          onCheckedChange={(checked) => {
                            setKinds((current) =>
                              checked
                                ? [...current, kind]
                                : current.filter((entry) => entry !== kind),
                            );
                          }}
                        />
                        {kind}
                      </label>
                    </li>
                  ))}
                </ul>
              )}
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-topics`}>
                {t("Denied topics")}
              </FieldLabel>
              <Input
                id={`${fieldId}-topics`}
                value={topics}
                placeholder={t("Separate topics with commas")}
                onChange={(event) => {
                  setTopics(event.target.value);
                }}
              />
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-depth`}>
                {t("Deepest tool chain")}
              </FieldLabel>
              <Input
                id={`${fieldId}-depth`}
                type="number"
                min={1}
                max={20}
                value={depth}
                onChange={(event) => {
                  setDepth(event.target.value);
                }}
              />
            </Field>
          </div>
        ) : (
          <dl className="grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
            <dt className="text-muted-foreground">{t("Prompt injection")}</dt>
            <dd>{injection === NONE ? t("Off") : injection}</dd>
            <dt className="text-muted-foreground">{t("Personal data")}</dt>
            <dd>{pii === NONE ? t("Off") : `${pii} (${kinds.join(", ")})`}</dd>
            <dt className="text-muted-foreground">{t("Denied topics")}</dt>
            <dd>{topics === "" ? t("None") : topics}</dd>
            <dt className="text-muted-foreground">{t("Deepest tool chain")}</dt>
            <dd>{depth === "" ? t("No limit") : depth}</dd>
          </dl>
        )}
        <DialogFooter>
          {step === 1 ? (
            <Button
              onClick={() => {
                setStep(2);
              }}
            >
              {t("Review")}
            </Button>
          ) : (
            <>
              <Button
                variant="ghost"
                onClick={() => {
                  setStep(1);
                }}
              >
                {t("Back")}
              </Button>
              <Button
                disabled={save.pending}
                onClick={() => {
                  void save.run({
                    agent: policy.agent,
                    stage: policy.stage,
                    enabled: true,
                    ...(injection === "block" || injection === "flag"
                      ? { injection }
                      : {}),
                    ...(pii === "block" || pii === "redact" || pii === "flag"
                      ? { pii: { action: pii, kinds: [...kinds] } }
                      : {}),
                    denyTopics: topics
                      .split(",")
                      .map((topic) => topic.trim())
                      .filter((topic) => topic !== ""),
                    ...(depth === "" ? {} : { maxToolDepth: Number(depth) }),
                  });
                }}
              >
                {t("Save policy")}
              </Button>
            </>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/** One agent's policy at one stage: its checks and the wizard that edits them. */
export function PolicyCard({ policy }: { policy: Policy }) {
  const t = useExtracted("guardrails");

  return (
    <Card size="sm">
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          {policy.title}
          <Badge variant="secondary">
            {policy.stage === "input" ? t("Input") : t("Output")}
          </Badge>
        </CardTitle>
        <CardDescription>
          {policy.inheritedFrom === undefined
            ? t("The policy saved for this agent.")
            : t("Inherited from {agent}.", { agent: policy.inheritedFrom })}
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        <Summary policy={policy} />
        <div>
          <PolicyWizard policy={policy} />
        </div>
      </CardContent>
    </Card>
  );
}
