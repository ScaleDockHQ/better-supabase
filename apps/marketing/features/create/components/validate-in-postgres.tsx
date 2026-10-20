"use client";

import {
  CircleAlertIcon,
  CircleCheckIcon,
  DatabaseIcon,
  InfoIcon,
  RotateCwIcon,
} from "lucide-react";
import { useState, useTransition } from "react";
import * as v from "valibot";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";

const validationResponse = v.union([
  v.object({
    ok: v.boolean(),
    issues: v.array(
      v.object({ module: v.string(), path: v.string(), message: v.string() }),
    ),
    skipped: v.array(v.object({ module: v.string(), reason: v.string() })),
    tables: v.number(),
  }),
  v.object({ error: v.string() }),
]);

type Validation = v.InferOutput<typeof validationResponse>;

type ValidationState =
  | { readonly status: "idle" }
  | { readonly status: "error"; readonly message: string }
  | {
      readonly status: "done";
      readonly result: Exclude<Validation, { error: string }>;
    };

async function validate(
  code: string,
  designCode: string,
): Promise<ValidationState> {
  try {
    const query = new URLSearchParams({ preset: code });

    if (designCode !== "") {
      query.set("design", designCode);
    }

    const response = await fetch(`/create/validate?${query.toString()}`);
    const body = v.parse(validationResponse, await response.json());

    return "error" in body
      ? { status: "error", message: body.error }
      : { status: "done", result: body };
  } catch (error) {
    return {
      status: "error",
      message:
        error instanceof Error
          ? error.message
          : "Postgres could not be reached.",
    };
  }
}

function ValidationResult({
  state,
  onRetry,
}: {
  state: ValidationState;
  onRetry: () => void;
}) {
  switch (state.status) {
    case "idle": {
      return null;
    }

    case "error": {
      return (
        <Alert variant="destructive">
          <CircleAlertIcon aria-hidden="true" />
          <AlertTitle>The design could not be validated</AlertTitle>
          <AlertDescription>{state.message}</AlertDescription>
          <AlertAction>
            <Button variant="outline" size="sm" onClick={onRetry}>
              <RotateCwIcon aria-hidden="true" />
              Retry
            </Button>
          </AlertAction>
        </Alert>
      );
    }

    case "done": {
      const { result } = state;

      return (
        <div className="flex flex-col gap-3">
          {result.ok ? (
            <Alert variant="success">
              <CircleCheckIcon aria-hidden="true" />
              <AlertTitle>Postgres accepted every file</AlertTitle>
              <AlertDescription>
                {result.tables > 0 ? (
                  <>
                    The files applied to an empty database and left{" "}
                    {result.tables} tables in{" "}
                    <code className="font-mono">public</code>.
                  </>
                ) : (
                  "The files applied to an empty database."
                )}
              </AlertDescription>
            </Alert>
          ) : (
            <Alert variant="destructive">
              <CircleAlertIcon aria-hidden="true" />
              <AlertTitle>
                Postgres rejected {result.issues.length} files
              </AlertTitle>
              <AlertDescription>
                <ul className="flex flex-col gap-2">
                  {result.issues.map((issue) => (
                    <li key={issue.path} className="flex flex-col gap-1">
                      <code className="font-mono text-xs">{issue.path}</code>
                      <span>{issue.message}</span>
                    </li>
                  ))}
                </ul>
              </AlertDescription>
            </Alert>
          )}
          {result.skipped.length > 0 ? (
            <Alert variant="info">
              <InfoIcon aria-hidden="true" />
              <AlertTitle>Skipped {result.skipped.length} modules</AlertTitle>
              <AlertDescription>
                <ul className="flex flex-col gap-1">
                  {result.skipped.map((module) => (
                    <li key={module.module}>
                      <code className="font-mono text-xs">{module.module}</code>
                      : {module.reason}
                    </li>
                  ))}
                </ul>
              </AlertDescription>
            </Alert>
          ) : null}
        </div>
      );
    }

    default: {
      const never: never = state;

      return never;
    }
  }
}

/**
 * Applies the rendered files to an in-memory Postgres (PGlite) on the server
 * and shows what it rejects, before anything reaches a real project.
 */
export function ValidateInPostgres({
  code,
  designCode,
}: {
  code: string;
  designCode: string;
}) {
  const [state, setState] = useState<ValidationState>({ status: "idle" });
  const [pending, startTransition] = useTransition();

  function run() {
    startTransition(async () => {
      const next = await validate(code, designCode);

      startTransition(() => {
        setState(next);
      });
    });
  }

  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-sm text-muted-foreground">
          Apply these files to an in-memory Postgres to see what it rejects.
        </p>
        <Button variant="outline" size="sm" disabled={pending} onClick={run}>
          <DatabaseIcon aria-hidden="true" />
          Validate in Postgres
        </Button>
      </div>
      {pending ? (
        <div aria-busy="true" className="flex flex-col gap-2">
          <span className="sr-only">Validating in Postgres</span>
          <Skeleton className="h-16 w-full" />
        </div>
      ) : (
        <ValidationResult state={state} onRetry={run} />
      )}
    </div>
  );
}
