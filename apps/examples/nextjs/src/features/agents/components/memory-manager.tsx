"use client";

import { useAction } from "better-supabase/react";
import { BrainIcon } from "lucide-react";
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
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Field, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

import type { MemoryFactRow, MemoryFileRow } from "../agents-queries";

import {
  forgetMemoryFact,
  removeMemoryFile,
  writeMemoryFile,
} from "../agents-actions";

function MemoryFile({
  file,
  canManage,
}: {
  file: MemoryFileRow;
  canManage: boolean;
}) {
  const t = useExtracted("agents");
  const errorMessage = useErrorMessage();
  // The editor is keyed by file id, so the draft starts from the saved text.
  // oxlint-disable-next-line react-doctor/no-derived-useState -- a draft the user edits
  const [content, setContent] = useState(file.content);

  const onError = (error: Parameters<typeof errorMessage>[0]) => {
    toast.error(errorMessage(error));
  };

  const save = useAction(writeMemoryFile, {
    onSuccess: () => {
      toast.success(t("Memory saved"));
    },
    onError,
  });

  const remove = useAction(removeMemoryFile, { onError });

  return (
    <li className="flex flex-col gap-2 px-4 py-3">
      <p className="font-mono text-xs text-muted-foreground">{file.path}</p>
      <Textarea
        value={content}
        rows={4}
        disabled={!canManage}
        aria-label={file.path}
        onChange={(event) => {
          setContent(event.target.value);
        }}
      />
      {canManage ? (
        <div className="flex justify-end gap-2">
          <Button
            size="sm"
            variant="outline"
            disabled={remove.pending}
            onClick={() => {
              void remove.run({ path: file.path });
            }}
          >
            {t("Delete")}
          </Button>
          <Button
            size="sm"
            disabled={save.pending || content === file.content}
            onClick={() => {
              void save.run({ path: file.path, content });
            }}
          >
            {t("Save")}
          </Button>
        </div>
      ) : null}
    </li>
  );
}

function NewMemoryFile() {
  const t = useExtracted("agents");
  const errorMessage = useErrorMessage();
  const fieldId = useId();
  const [path, setPath] = useState("/memories/");
  const [content, setContent] = useState("");

  const save = useAction(writeMemoryFile, {
    onSuccess: () => {
      setPath("/memories/");
      setContent("");
      toast.success(t("Memory saved"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <form
      className="flex flex-col gap-3 px-4 py-3"
      onSubmit={(event) => {
        event.preventDefault();
        void save.run({ path, content });
      }}
    >
      <Field>
        <FieldLabel htmlFor={`${fieldId}-path`}>{t("Path")}</FieldLabel>
        <Input
          id={`${fieldId}-path`}
          value={path}
          required
          onChange={(event) => {
            setPath(event.target.value);
          }}
        />
      </Field>
      <Field>
        <FieldLabel htmlFor={`${fieldId}-content`}>{t("Content")}</FieldLabel>
        <Textarea
          id={`${fieldId}-content`}
          value={content}
          rows={3}
          required
          onChange={(event) => {
            setContent(event.target.value);
          }}
        />
      </Field>
      <div className="flex justify-end">
        <Button type="submit" size="sm" disabled={save.pending}>
          {t("Add memory file")}
        </Button>
      </div>
    </form>
  );
}

function MemoryFact({
  fact,
  canManage,
}: {
  fact: MemoryFactRow;
  canManage: boolean;
}) {
  const t = useExtracted("agents");
  const errorMessage = useErrorMessage();

  const forget = useAction(forgetMemoryFact, {
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <li className="flex items-start gap-3 px-4 py-3 text-sm">
      <div className="flex min-w-0 flex-1 flex-col gap-1">
        <p>{fact.content}</p>
        <p className="text-xs text-muted-foreground tabular-nums">
          {[
            fact.category,
            fact.confidence === undefined
              ? undefined
              : t("confidence {value, number}", { value: fact.confidence }),
            t("used {count, number} times", { count: fact.uses }),
          ]
            .filter((part) => part !== undefined)
            .join(" · ")}
        </p>
      </div>
      {canManage ? (
        <Button
          size="sm"
          variant="outline"
          disabled={forget.pending}
          onClick={() => {
            void forget.run({ id: fact.id });
          }}
        >
          {t("Forget")}
        </Button>
      ) : null}
    </li>
  );
}

/** Core memory files the assistant reads every answer, and the facts it saved. */
export function MemoryManager({
  files,
  facts,
  canManage,
}: {
  files: readonly MemoryFileRow[];
  facts: readonly MemoryFactRow[];
  canManage: boolean;
}) {
  const t = useExtracted("agents");

  return (
    <div className="grid gap-6 lg:grid-cols-2">
      <Card>
        <CardHeader>
          <CardTitle>{t("Core memory")}</CardTitle>
          <CardDescription>
            {t(
              "Files under /memories that the assistant reads on every answer.",
            )}
          </CardDescription>
        </CardHeader>
        <CardContent className="p-0">
          <ul className="divide-y">
            {files.map((file) => (
              <MemoryFile key={file.id} file={file} canManage={canManage} />
            ))}
          </ul>
          {canManage ? <NewMemoryFile /> : null}
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>{t("Remembered facts")}</CardTitle>
          <CardDescription>
            {t("Facts the assistant saved while it talked to people.")}
          </CardDescription>
        </CardHeader>
        <CardContent className="p-0">
          {facts.length === 0 ? (
            <Empty>
              <EmptyHeader>
                <EmptyMedia variant="icon">
                  <BrainIcon />
                </EmptyMedia>
                <EmptyTitle>{t("Nothing remembered yet")}</EmptyTitle>
                <EmptyDescription>
                  {t("Facts show up here after the assistant saves one.")}
                </EmptyDescription>
              </EmptyHeader>
            </Empty>
          ) : (
            <ul className="divide-y">
              {facts.map((fact) => (
                <MemoryFact key={fact.id} fact={fact} canManage={canManage} />
              ))}
            </ul>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
