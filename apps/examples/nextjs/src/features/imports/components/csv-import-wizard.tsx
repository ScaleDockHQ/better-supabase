// #region recipe:csv-import-wizard
"use client";

import type { DbError } from "better-supabase";

import { parseCsv, suggestMapping } from "better-supabase/blocks/imports";
import { useAction } from "better-supabase/react";
import {
  ArrowLeftIcon,
  CheckIcon,
  FileSpreadsheetIcon,
  PlayIcon,
  RotateCcwIcon,
  UploadIcon,
} from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useReducer, useRef } from "react";

import { Alert, AlertDescription, AlertTitle } from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import {
  Stepper,
  StepperContent,
  StepperIndicator,
  StepperItem,
  StepperNav,
  StepperPanel,
  StepperSeparator,
  StepperTitle,
  StepperTrigger,
} from "@/components/reui/stepper";
import { Button, buttonVariants } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Field, FieldLabel } from "@/components/ui/field";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Link } from "@/i18n/navigation";
import { useErrorMessage } from "@/lib/use-error-message";

import {
  type ImportOutcome,
  type ImportPreview,
  previewCustomerImport,
  runCustomerImport,
} from "../imports-actions";
import {
  type ColumnMapping,
  CUSTOMER_IMPORT_FIELDS,
  type CustomerImportField,
} from "../imports-fields";

const SKIP = "skip";
const MAX_BYTES = 500_000;

type Choice = CustomerImportField | typeof SKIP;

type Mapping = Readonly<Record<string, Choice>>;

const CHOICES: readonly Choice[] = [...CUSTOMER_IMPORT_FIELDS, SKIP];

interface CsvFile {
  readonly name: string;
  readonly text: string;
  readonly headers: readonly string[];
  readonly rowCount: number;
}

function isField(value: unknown): value is CustomerImportField | typeof SKIP {
  return (
    value === SKIP || CUSTOMER_IMPORT_FIELDS.some((field) => field === value)
  );
}

/** The mapping without skipped columns, as the server actions take it. */
function mappedOnly(mapping: Mapping): ColumnMapping {
  const result: Record<string, CustomerImportField> = {};

  for (const [header, field] of Object.entries(mapping)) {
    if (field !== SKIP) {
      result[header] = field;
    }
  }

  return result;
}

interface WizardState {
  readonly step: number;
  readonly file: CsvFile | null;
  readonly fileError: string | null;
  readonly mapping: Mapping;
  readonly preview: ImportPreview | null;
  readonly outcome: ImportOutcome | null;
  readonly failure: DbError | null;
}

type WizardEvent =
  | { readonly type: "step"; readonly step: number }
  | { readonly type: "reset" }
  | { readonly type: "file-error"; readonly message: string | null }
  | {
      readonly type: "loaded";
      readonly file: CsvFile;
      readonly mapping: Mapping;
    }
  | { readonly type: "map"; readonly header: string; readonly field: Choice }
  | { readonly type: "running" }
  | { readonly type: "previewed"; readonly preview: ImportPreview }
  | { readonly type: "ran"; readonly outcome: ImportOutcome }
  | { readonly type: "failed"; readonly error: DbError };

const INITIAL: WizardState = {
  step: 1,
  file: null,
  fileError: null,
  mapping: {},
  preview: null,
  outcome: null,
  failure: null,
};

function wizard(state: WizardState, event: WizardEvent): WizardState {
  switch (event.type) {
    case "step": {
      return { ...state, step: event.step };
    }

    case "reset": {
      return INITIAL;
    }

    case "file-error": {
      return { ...state, fileError: event.message };
    }

    case "loaded": {
      return { ...INITIAL, step: 2, file: event.file, mapping: event.mapping };
    }

    case "map": {
      return {
        ...state,
        mapping: { ...state.mapping, [event.header]: event.field },
      };
    }

    case "running": {
      return { ...state, failure: null };
    }

    case "previewed": {
      return { ...state, step: 3, preview: event.preview };
    }

    case "ran": {
      return { ...state, step: 4, outcome: event.outcome };
    }

    case "failed": {
      return { ...state, failure: event.error };
    }

    default: {
      const unhandled: never = event;

      return unhandled;
    }
  }
}

/**
 * Imports customers from a CSV file in four steps: upload, map the columns,
 * preview the validated rows, then run the import and show what it created.
 */
export function CsvImportWizard() {
  const t = useExtracted("imports");
  const message = useErrorMessage();
  const inputId = useId();
  const fileInput = useRef<HTMLInputElement>(null);
  const [state, dispatch] = useReducer(wizard, INITIAL);
  const { step, file, fileError, mapping, preview, outcome, failure } = state;
  const previewAction = useAction(previewCustomerImport);
  const runAction = useAction(runCustomerImport);

  const fieldLabels: Record<Choice, string> = {
    name: t("Name"),
    status: t("Status"),
    kvk: t("KvK number"),
    skip: t("Don't import"),
  };

  const fieldItems = CHOICES.map((value) => ({
    value,
    label: fieldLabels[value],
  }));

  const mapped = Object.values(mapping).filter((field) => field !== SKIP);
  const nameMapped = mapped.includes("name");

  const duplicate = mapped.some(
    (field, index) => mapped.indexOf(field) !== index,
  );

  const reached = outcome ? 4 : preview ? 3 : file ? 2 : 1;

  const reset = () => {
    dispatch({ type: "reset" });
  };

  const choose = async (picked: File | undefined) => {
    dispatch({ type: "file-error", message: null });

    if (picked === undefined) {
      return;
    }

    if (picked.size > MAX_BYTES) {
      dispatch({
        type: "file-error",
        message: t("Pick a file smaller than 500 KB."),
      });

      return;
    }

    const text = await picked.text();
    const [headers = [], ...rows] = parseCsv(text);

    if (headers.length === 0 || rows.length === 0) {
      dispatch({
        type: "file-error",
        message: t("The file needs a header row and at least one row."),
      });

      return;
    }

    const suggested = suggestMapping(headers, CUSTOMER_IMPORT_FIELDS);
    const initial: Record<string, Choice> = {};

    for (const header of headers) {
      const field = suggested[header];

      initial[header] = isField(field) ? field : SKIP;
    }

    dispatch({
      type: "loaded",
      file: { name: picked.name, text, headers, rowCount: rows.length },
      mapping: initial,
    });
  };

  const runPreview = async () => {
    if (file === null) {
      return;
    }

    dispatch({ type: "running" });

    const result = await previewAction.run({
      csv: file.text,
      mapping: mappedOnly(mapping),
    });

    if (result.ok) {
      dispatch({ type: "previewed", preview: result.data });
    } else {
      dispatch({ type: "failed", error: result.error });
    }
  };

  const runImport = async () => {
    if (file === null) {
      return;
    }

    dispatch({ type: "running" });

    const result = await runAction.run({
      csv: file.text,
      mapping: mappedOnly(mapping),
    });

    if (result.ok) {
      dispatch({ type: "ran", outcome: result.data });
    } else {
      dispatch({ type: "failed", error: result.error });
    }
  };

  const failureAlert = failure ? (
    <Alert variant="destructive">
      <AlertTitle>{t("That didn't work")}</AlertTitle>
      <AlertDescription className="flex flex-col items-start gap-2">
        {message(failure)}
        <Button
          variant="outline"
          size="sm"
          disabled={previewAction.pending || runAction.pending}
          onClick={() => {
            void (step === 3 ? runImport() : runPreview());
          }}
        >
          <RotateCcwIcon />
          {t("Retry")}
        </Button>
      </AlertDescription>
    </Alert>
  ) : null;

  const steps = [
    { step: 1, title: t("Upload") },
    { step: 2, title: t("Map columns") },
    { step: 3, title: t("Preview") },
    { step: 4, title: t("Results") },
  ];

  return (
    <Card data-recipe="csv-import-wizard">
      <CardHeader>
        <CardTitle>{t("Import customers")}</CardTitle>
        <CardDescription>
          {t(
            "Upload a CSV file with a name column, and optionally status and KvK number.",
          )}
        </CardDescription>
      </CardHeader>
      <CardContent>
        <Stepper
          value={step}
          onValueChange={(next) => {
            dispatch({ type: "step", step: next });
          }}
          className="flex flex-col gap-6"
        >
          <StepperNav>
            {steps.map((item) => (
              <StepperItem
                key={item.step}
                step={item.step}
                disabled={item.step > reached || outcome !== null}
              >
                <StepperTrigger className="flex items-center gap-2">
                  <StepperIndicator>{item.step}</StepperIndicator>
                  <StepperTitle>{item.title}</StepperTitle>
                </StepperTrigger>
                {item.step < steps.length ? <StepperSeparator /> : null}
              </StepperItem>
            ))}
          </StepperNav>
          <StepperPanel>
            <StepperContent value={1}>
              <Empty className="border">
                <EmptyHeader>
                  <EmptyMedia variant="icon">
                    <FileSpreadsheetIcon />
                  </EmptyMedia>
                  <EmptyTitle>
                    {file ? file.name : t("Choose a CSV file")}
                  </EmptyTitle>
                  <EmptyDescription>
                    {file
                      ? t("{count, plural, =1 {# row} other {# rows}}", {
                          count: file.rowCount,
                        })
                      : t("The first row names the columns.")}
                  </EmptyDescription>
                </EmptyHeader>
                <EmptyContent>
                  <input
                    ref={fileInput}
                    id={inputId}
                    type="file"
                    accept=".csv,text/csv"
                    className="sr-only"
                    onChange={(event) => {
                      void choose(event.target.files?.[0]);
                      event.target.value = "";
                    }}
                  />
                  <Button onClick={() => fileInput.current?.click()}>
                    <UploadIcon />
                    {file ? t("Choose another file") : t("Choose file")}
                  </Button>
                  {fileError ? (
                    <p className="text-sm text-destructive">{fileError}</p>
                  ) : null}
                </EmptyContent>
              </Empty>
            </StepperContent>
            <StepperContent value={2} className="flex flex-col gap-4">
              <div className="grid gap-4 sm:grid-cols-2">
                {file?.headers.map((header) => (
                  <Field key={header}>
                    <FieldLabel htmlFor={`${inputId}-${header}`}>
                      {header}
                    </FieldLabel>
                    <Select
                      value={mapping[header] ?? SKIP}
                      items={fieldItems}
                      onValueChange={(value) => {
                        if (isField(value)) {
                          dispatch({ type: "map", header, field: value });
                        }
                      }}
                    >
                      <SelectTrigger
                        id={`${inputId}-${header}`}
                        className="w-full"
                      >
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {fieldItems.map((item) => (
                          <SelectItem key={item.value} value={item.value}>
                            {item.label}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </Field>
                ))}
              </div>
              {nameMapped ? null : (
                <p className="text-sm text-muted-foreground">
                  {t("Map one column to Name to continue.")}
                </p>
              )}
              {duplicate ? (
                <p className="text-sm text-destructive">
                  {t("Map each customer field to one column only.")}
                </p>
              ) : null}
              {failureAlert}
            </StepperContent>
            <StepperContent value={3} className="flex flex-col gap-4">
              {preview ? (
                <>
                  <div className="flex flex-wrap items-center gap-2">
                    <Badge variant="success-light">
                      {t(
                        "{count, plural, =1 {# valid row} other {# valid rows}}",
                        { count: preview.valid },
                      )}
                    </Badge>
                    {preview.errors.length > 0 ? (
                      <Badge variant="destructive-light">
                        {t(
                          "{count, plural, =1 {# row with errors} other {# rows with errors}}",
                          { count: preview.errors.length },
                        )}
                      </Badge>
                    ) : null}
                  </div>
                  {preview.errors.length > 0 ? (
                    <Alert variant="destructive">
                      <AlertTitle>
                        {t("Fix these rows and upload the file again")}
                      </AlertTitle>
                      <AlertDescription>
                        <ul className="flex flex-col gap-1">
                          {preview.errors.slice(0, 10).map((error) => (
                            <li key={error.row}>
                              {t("Row {row}: {message}", {
                                row: String(error.row),
                                message: error.message,
                              })}
                            </li>
                          ))}
                        </ul>
                      </AlertDescription>
                    </Alert>
                  ) : null}
                  {preview.rows.length > 0 ? (
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>{t("Name")}</TableHead>
                          <TableHead>{t("Status")}</TableHead>
                          <TableHead>{t("KvK number")}</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {preview.rows.map((row, index) => (
                          // oxlint-disable-next-line react/no-array-index-key -- preview rows have no unique column and the list never reorders (1 finding)
                          <TableRow key={`${row.name}-${index}`}>
                            <TableCell className="font-medium">
                              {row.name}
                            </TableCell>
                            <TableCell>
                              {row.status === "active"
                                ? t("Active")
                                : t("Lead")}
                            </TableCell>
                            <TableCell className="text-muted-foreground">
                              {row.kvk ?? t("None")}
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  ) : null}
                  {preview.valid > preview.rows.length ? (
                    <p className="text-xs text-muted-foreground">
                      {t("Showing the first {shown} of {total} rows.", {
                        shown: String(preview.rows.length),
                        total: String(preview.valid),
                      })}
                    </p>
                  ) : null}
                </>
              ) : null}
              {failureAlert}
            </StepperContent>
            <StepperContent value={4}>
              {outcome ? (
                <Alert
                  variant={
                    outcome.status === "completed" ? "success" : "destructive"
                  }
                >
                  <AlertTitle>
                    {outcome.status === "completed"
                      ? t("Import finished")
                      : t("Import failed")}
                  </AlertTitle>
                  <AlertDescription className="flex flex-col items-start gap-2">
                    {outcome.status === "completed"
                      ? t(
                          "Created {imported, plural, =1 {# customer} other {# customers}}. Skipped {skipped, plural, =1 {# row} other {# rows}} whose name already exists.",
                          {
                            imported: outcome.imported,
                            skipped: outcome.skipped,
                          },
                        )
                      : t(
                          "No customers were created. Fix the rows and try again.",
                        )}
                    <Link
                      href="/customers"
                      className={buttonVariants({
                        variant: "outline",
                        size: "sm",
                      })}
                    >
                      {t("View customers")}
                    </Link>
                  </AlertDescription>
                </Alert>
              ) : null}
            </StepperContent>
          </StepperPanel>
        </Stepper>
      </CardContent>
      <CardFooter className="justify-between gap-2">
        {step === 2 || step === 3 ? (
          <Button
            variant="outline"
            onClick={() => {
              dispatch({ type: "step", step: step - 1 });
            }}
          >
            <ArrowLeftIcon />
            {t("Back")}
          </Button>
        ) : (
          <span />
        )}
        {step === 2 ? (
          <Button
            disabled={!nameMapped || duplicate || previewAction.pending}
            onClick={() => {
              void runPreview();
            }}
          >
            <CheckIcon />
            {previewAction.pending ? t("Checking") : t("Check rows")}
          </Button>
        ) : null}
        {step === 3 ? (
          <Button
            disabled={
              preview === null ||
              preview.valid === 0 ||
              preview.errors.length > 0 ||
              runAction.pending
            }
            onClick={() => {
              void runImport();
            }}
          >
            <PlayIcon />
            {runAction.pending ? t("Importing") : t("Import customers")}
          </Button>
        ) : null}
        {step === 4 ? (
          <Button variant="outline" onClick={reset}>
            <RotateCcwIcon />
            {t("Import another file")}
          </Button>
        ) : null}
      </CardFooter>
    </Card>
  );
}
// #endregion recipe:csv-import-wizard
