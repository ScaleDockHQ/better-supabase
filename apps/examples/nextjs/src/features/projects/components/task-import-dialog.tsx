"use client";

import { parseCsv, suggestMapping } from "better-supabase/blocks/imports";
import { useAction } from "better-supabase/react";
import { TriangleAlertIcon, UploadIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useState } from "react";
import { toast } from "sonner";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Field, FieldLabel } from "@/components/ui/field";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Textarea } from "@/components/ui/textarea";
import { useErrorMessage } from "@/lib/use-error-message";

import type { TaskImportField } from "../project-types";

import { TASK_IMPORT_FIELDS } from "../project-types";
import { previewTaskImport, runTaskImport } from "../task-import-actions";

// #region recipe:upsert-import

const SKIP = "skip";

type Choice = TaskImportField | typeof SKIP;

function isChoice(value: unknown): value is Choice {
  return value === SKIP || TASK_IMPORT_FIELDS.some((field) => field === value);
}

/** The mapped columns, without the skipped ones. */
function mappedOnly(
  mapping: Readonly<Record<string, Choice>>,
): Record<string, TaskImportField> {
  return Object.fromEntries(
    Object.entries(mapping).flatMap(([header, choice]) =>
      choice === SKIP ? [] : [[header, choice]],
    ),
  );
}

/**
 * Imports tasks into the project from pasted CSV: map the columns, preview what
 * the file creates and changes, then run it. A task with the same title in the
 * project is updated instead of added twice.
 */
export function TaskImportDialog({ projectId }: { projectId: string }) {
  const t = useExtracted("projects");
  const id = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);
  const [csv, setCsv] = useState("");
  const [mapping, setMapping] = useState<Record<string, Choice>>({});
  const preview = useAction(previewTaskImport);

  const run = useAction(runTaskImport, {
    onSuccess: ({ status, imported }) => {
      if (status === "completed") {
        toast.success(
          t("{count, plural, one {# task} other {# tasks}} imported", {
            count: imported,
          }),
        );
        setOpen(false);
        setCsv("");
        setMapping({});
        preview.reset();
      } else {
        toast.error(t("The file has rows that need fixing."));
      }
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  const [headers = []] = csv.trim() === "" ? [] : parseCsv(csv);
  const titleMapped = Object.values(mapping).includes("title");

  const label = {
    title: t("Title"),
    status: t("Status"),
    dueOn: t("Due date"),
  } as const satisfies Record<TaskImportField, string>;

  const choices = [
    { value: SKIP, label: t("Skip") },
    ...TASK_IMPORT_FIELDS.map((field) => ({
      value: field,
      label: label[field],
    })),
  ];

  const changeCsv = (text: string) => {
    setCsv(text);
    preview.reset();

    const [first = []] = text.trim() === "" ? [] : parseCsv(text);
    const suggested = suggestMapping(first, TASK_IMPORT_FIELDS);

    setMapping(
      Object.fromEntries(
        first.map((header) => {
          const field = suggested[header];

          return [header, isChoice(field) ? field : SKIP];
        }),
      ),
    );
  };

  const input = { projectId, csv, mapping: mappedOnly(mapping) };

  const runPreview = () => {
    void preview.run(input);
  };

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger render={<Button size="sm" variant="outline" />}>
        <UploadIcon />
        {t("Import")}
      </DialogTrigger>
      <DialogContent data-recipe="upsert-import">
        <DialogHeader>
          <DialogTitle>{t("Import tasks")}</DialogTitle>
          <DialogDescription>
            {t(
              "Paste CSV with a title column. A title the project already has updates that task.",
            )}
          </DialogDescription>
        </DialogHeader>
        <div className="flex flex-col gap-4">
          <Field>
            <FieldLabel htmlFor={`${id}-csv`}>{t("CSV")}</FieldLabel>
            <Textarea
              id={`${id}-csv`}
              rows={5}
              value={csv}
              placeholder={"title,status,due\nWrite the brief,todo,2026-11-02"}
              onChange={(event) => {
                changeCsv(event.target.value);
              }}
            />
          </Field>
          {headers.length > 0 ? (
            <div className="grid gap-3 sm:grid-cols-2">
              {headers.map((header) => (
                <Field key={header}>
                  <FieldLabel htmlFor={`${id}-${header}`}>{header}</FieldLabel>
                  <Select
                    value={mapping[header] ?? SKIP}
                    items={choices}
                    onValueChange={(value) => {
                      if (isChoice(value)) {
                        setMapping((current) => ({
                          ...current,
                          [header]: value,
                        }));
                        preview.reset();
                      }
                    }}
                  >
                    <SelectTrigger
                      id={`${id}-${header}`}
                      size="sm"
                      className="w-full"
                    >
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {choices.map((choice) => (
                        <SelectItem key={choice.value} value={choice.value}>
                          {choice.label}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </Field>
              ))}
            </div>
          ) : null}
          {preview.error ? (
            <Alert variant="destructive">
              <TriangleAlertIcon />
              <AlertTitle>{t("The preview didn't load")}</AlertTitle>
              <AlertDescription>{errorMessage(preview.error)}</AlertDescription>
              <AlertAction>
                <Button size="sm" variant="outline" onClick={runPreview}>
                  {t("Retry")}
                </Button>
              </AlertAction>
            </Alert>
          ) : preview.pending ? (
            <Skeleton className="h-8" />
          ) : preview.data ? (
            <div className="flex flex-col gap-2" data-testid="import-preview">
              <div className="flex flex-wrap items-center gap-2">
                <Badge variant="success-light">
                  {t("{count, plural, one {# new} other {# new}}", {
                    count: preview.data.created,
                  })}
                </Badge>
                <Badge variant="info-light">
                  {t("{count, plural, one {# changed} other {# changed}}", {
                    count: preview.data.changed,
                  })}
                </Badge>
                <Badge variant="secondary">
                  {t("{count, plural, one {# unchanged} other {# unchanged}}", {
                    count: preview.data.unchanged,
                  })}
                </Badge>
                {preview.data.errors.length > 0 ? (
                  <Badge variant="destructive-light">
                    {t("{count, plural, one {# error} other {# errors}}", {
                      count: preview.data.errors.length,
                    })}
                  </Badge>
                ) : null}
              </div>
              {preview.data.errors.slice(0, 5).map((error) => (
                <p
                  key={`${error.row}:${error.message}`}
                  className="text-xs text-destructive"
                >
                  {t("Row {row}: {message}", {
                    row: String(error.row),
                    message: error.message,
                  })}
                </p>
              ))}
            </div>
          ) : null}
        </div>
        <DialogFooter>
          <DialogClose render={<Button type="button" variant="outline" />}>
            {t("Cancel")}
          </DialogClose>
          {preview.data && preview.data.errors.length === 0 ? (
            <Button
              disabled={run.pending}
              onClick={() => {
                void run.run(input);
              }}
            >
              {t("Import")}
            </Button>
          ) : (
            <Button
              disabled={!titleMapped || preview.pending}
              onClick={runPreview}
            >
              {t("Preview")}
            </Button>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

// #endregion recipe:upsert-import
