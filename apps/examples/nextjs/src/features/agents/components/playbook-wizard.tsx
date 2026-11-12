"use client";

import { useAction } from "better-supabase/react";
import { PlusIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useRouter } from "next/navigation";
import { useId, useState } from "react";

import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Field, FieldError, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

import type { Playbook } from "../agents-tools";

import { createAgent } from "../agents-actions";
import { PLAYBOOKS } from "../agents-tools";

const slugOf = (name: string): string =>
  name
    .toLowerCase()
    .replaceAll(/[^a-z0-9]+/g, "-")
    .replaceAll(/^-+|-+$/g, "")
    .slice(0, 40);

/** Two steps: pick a playbook, then name the agent and adjust its instructions. */
export function PlaybookWizard() {
  const t = useExtracted("agents");
  const router = useRouter();
  const errorMessage = useErrorMessage();
  const fieldId = useId();
  const [open, setOpen] = useState(false);
  const [playbook, setPlaybook] = useState<Playbook | undefined>();
  const [name, setName] = useState("");
  const [instructions, setInstructions] = useState("");

  const create = useAction(createAgent, {
    onSuccess: (id) => {
      toast.success(t("Agent created"));
      setOpen(false);
      router.push(`/assistant/agents/${id}`);
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  const pick = (entry: Playbook) => {
    setPlaybook(entry);
    setName(entry.name);
    setInstructions(entry.instructions);
  };

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);

        if (!next) {
          setPlaybook(undefined);
        }
      }}
    >
      <DialogTrigger render={<Button size="sm" />}>
        <PlusIcon />
        {t("New agent")}
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t("New agent")}</DialogTitle>
          <DialogDescription>
            {playbook === undefined
              ? t("Step 1 of 2: pick a playbook to start from.")
              : t("Step 2 of 2: name the agent and review its instructions.")}
          </DialogDescription>
        </DialogHeader>
        {playbook === undefined ? (
          <ul className="flex flex-col gap-2">
            {PLAYBOOKS.map((entry) => (
              <li key={entry.id}>
                <Button
                  variant="outline"
                  className="h-auto w-full flex-col items-start gap-0.5 py-2 text-left whitespace-normal"
                  onClick={() => {
                    pick(entry);
                  }}
                >
                  <span className="font-medium">{entry.name}</span>
                  <span className="text-xs font-normal text-muted-foreground">
                    {entry.instructions}
                  </span>
                </Button>
              </li>
            ))}
          </ul>
        ) : (
          <form
            className="flex flex-col gap-4"
            onSubmit={(event) => {
              event.preventDefault();

              void create.run({
                slug: slugOf(name),
                name,
                instructions,
                tools: [...playbook.tools],
                starters: [...playbook.starters],
              });
            }}
          >
            <Field>
              <FieldLabel htmlFor={`${fieldId}-name`}>{t("Name")}</FieldLabel>
              <Input
                id={`${fieldId}-name`}
                value={name}
                maxLength={80}
                required
                onChange={(event) => {
                  setName(event.target.value);
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
                rows={6}
                required
                onChange={(event) => {
                  setInstructions(event.target.value);
                }}
              />
              {create.error === undefined ? null : (
                <FieldError>{errorMessage(create.error)}</FieldError>
              )}
            </Field>
            <DialogFooter>
              <Button
                type="button"
                variant="ghost"
                onClick={() => {
                  setPlaybook(undefined);
                }}
              >
                {t("Back")}
              </Button>
              <Button
                type="submit"
                disabled={create.pending || slugOf(name).length < 2}
              >
                {t("Create agent")}
              </Button>
            </DialogFooter>
          </form>
        )}
      </DialogContent>
    </Dialog>
  );
}
