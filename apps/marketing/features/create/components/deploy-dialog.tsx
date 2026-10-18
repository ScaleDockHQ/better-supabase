"use client";

import type { ReactElement } from "react";

import {
  designInstallCommand,
  type ResolvedPreset,
} from "better-supabase/preset";
import {
  CircleAlertIcon,
  CircleCheckIcon,
  ExternalLinkIcon,
  LoaderCircleIcon,
  RotateCwIcon,
  TriangleAlertIcon,
  UploadIcon,
} from "lucide-react";
import { Suspense, use, useId, useReducer, useRef, useState } from "react";
import { siSupabase } from "simple-icons";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import { Frame, FramePanel } from "@/components/reui/frame";
import { BrandLogo } from "@/components/site/brand-icons";
import { CopyButton } from "@/components/site/copy-button";
import { Button } from "@/components/ui/button";
import { buttonVariants } from "@/components/ui/button-variants";
import { Checkbox } from "@/components/ui/checkbox";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Field, FieldDescription, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { commandFor, withPackage } from "@/lib/create";
import {
  type CreatedProjectResponse,
  dashboardUrl,
  type DeployResponse,
  type ErrorResponse,
  type ProjectsResponse,
  type ProjectStatusResponse,
  suggestedProjectName,
} from "@/lib/supabase-deploy";
import {
  SMART_REGIONS,
  type SmartRegion,
  type SupabaseProject,
} from "@/lib/supabase-management";

import { CommandRow } from "./get-code-dialog";

const API = "/create/supabase";

const REGION_LABELS: Record<SmartRegion, string> = {
  americas: "Americas",
  emea: "Europe, Middle East and Africa",
  apac: "Asia-Pacific",
};

/** A new project takes a few minutes; past this the dialog stops waiting. */
const START_POLLS = 60;
const POLL_MS = 5000;

type Outcome<T> =
  | { readonly ok: true; readonly value: T }
  | { readonly ok: false; readonly error: ErrorResponse };

async function request<T>(
  path: string,
  init?: RequestInit,
): Promise<Outcome<T>> {
  try {
    const response = await fetch(`${API}${path}`, {
      ...init,
      headers: { "Content-Type": "application/json" },
    });

    const body: unknown =
      response.status === 204 ? null : await response.json();

    // SAFETY: the routes in app/(create)/create/supabase answer with these
    // interfaces from lib/supabase-deploy.ts, and every error with ErrorResponse.
    return response.ok
      ? { ok: true, value: body as T }
      : { ok: false, error: body as ErrorResponse };
  } catch (error) {
    return {
      ok: false,
      error: {
        error: "supabase",
        message:
          error instanceof Error ? error.message : "The request didn't finish.",
      },
    };
  }
}

const projectRequests = new Map<number, Promise<Outcome<ProjectsResponse>>>();

/** One request per attempt, so `use` sees the same promise on every render. */
function projectsFor(attempt: number): Promise<Outcome<ProjectsResponse>> {
  const known = projectRequests.get(attempt);

  if (known !== undefined) {
    return known;
  }

  const next = request<ProjectsResponse>("/projects");
  projectRequests.set(attempt, next);

  return next;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

type Phase =
  | { readonly step: "idle" }
  | { readonly step: "creating" }
  | {
      readonly step: "starting";
      readonly ref: string;
      readonly password: string;
    }
  | {
      readonly step: "deploying";
      readonly ref: string;
      readonly password: string | undefined;
    }
  | {
      readonly step: "done";
      readonly result: DeployResponse;
      readonly password: string | undefined;
    }
  | {
      readonly step: "failed";
      readonly message: string;
      readonly password: string | undefined;
    };

function ConnectStep({
  failed,
  returnTo,
}: {
  failed: boolean;
  returnTo: string;
}): ReactElement {
  return (
    <div className="flex flex-col gap-4">
      {failed ? (
        <Alert variant="destructive">
          <CircleAlertIcon aria-hidden="true" />
          <AlertTitle>Supabase didn&apos;t connect</AlertTitle>
          <AlertDescription>
            The consent screen was closed or refused. Try again.
          </AlertDescription>
        </Alert>
      ) : null}
      <p className="text-sm leading-6 text-muted-foreground">
        Sign in to Supabase and allow better-supabase to manage your projects.
        The token stays in an encrypted cookie in this browser, and the SQL is
        the same as the Migrations tab under Get code.
      </p>
      <form method="post" action={`${API}/connect`} className="self-start">
        <input type="hidden" name="return" value={returnTo} />
        <Button type="submit">
          <BrandLogo mark={siSupabase} className="size-4" />
          Connect Supabase
        </Button>
      </form>
    </div>
  );
}

function ProjectsSkeleton(): ReactElement {
  return (
    <div aria-busy="true" className="flex flex-col gap-3">
      <span className="sr-only">Loading your Supabase projects</span>
      <Skeleton className="h-9 w-56" />
      <Skeleton className="h-9 w-full" />
      <Skeleton className="h-9 w-full" />
    </div>
  );
}

function PhaseStatus({ phase }: { phase: Phase }): ReactElement | null {
  const text =
    phase.step === "creating"
      ? "Creating the project"
      : phase.step === "starting"
        ? "Waiting for the database to start. A new project takes a few minutes."
        : phase.step === "deploying"
          ? "Applying the migration"
          : undefined;

  return text === undefined ? null : (
    <output className="flex items-center gap-2 text-sm text-muted-foreground">
      <LoaderCircleIcon
        aria-hidden="true"
        className="size-4 animate-spin motion-reduce:animate-none"
      />
      {text}
    </output>
  );
}

function PasswordRow({ password }: { password: string }): ReactElement {
  return (
    <section aria-labelledby="deploy-password" className="flex flex-col gap-2">
      <h3 id="deploy-password" className="text-sm font-medium">
        Database password
      </h3>
      <p className="text-xs text-muted-foreground">
        The new project&apos;s password, shown once and stored nowhere. Save it
        now; the dashboard can reset it later.
      </p>
      <div className="flex items-center gap-1 rounded-md border border-border bg-muted/50 pl-3">
        <code className="min-w-0 flex-1 truncate py-2 font-mono text-code">
          {password}
        </code>
        <CopyButton text={password} label="Copy the database password" />
      </div>
    </section>
  );
}

function DeployResult({
  result,
  password,
  install,
}: {
  result: DeployResponse;
  password: string | undefined;
  install: string;
}): ReactElement {
  const problems = result.lints.filter((lint) => lint.level !== "INFO");

  return (
    <div className="flex flex-col gap-4">
      <Alert variant="success">
        <CircleCheckIcon aria-hidden="true" />
        <AlertTitle>Deployed to {result.ref}</AlertTitle>
        <AlertDescription>
          The schema is live as the migration{" "}
          <code className="font-mono">{result.migration}</code>.
        </AlertDescription>
      </Alert>
      <div className="flex flex-wrap gap-2">
        <a
          href={dashboardUrl(result.ref)}
          target="_blank"
          rel="noreferrer"
          className={buttonVariants({ variant: "outline", size: "sm" })}
        >
          <ExternalLinkIcon aria-hidden="true" />
          Open the project
        </a>
        <a
          href={dashboardUrl(result.ref, "/settings/api-keys")}
          target="_blank"
          rel="noreferrer"
          className={buttonVariants({ variant: "outline", size: "sm" })}
        >
          <ExternalLinkIcon aria-hidden="true" />
          API keys
        </a>
      </div>
      {password === undefined ? null : <PasswordRow password={password} />}
      <section aria-labelledby="deploy-advisor" className="flex flex-col gap-2">
        <h3 id="deploy-advisor" className="text-sm font-medium">
          Security advisor
        </h3>
        {problems.length === 0 ? (
          <p className="text-xs text-muted-foreground">
            No security warnings on the project.
          </p>
        ) : (
          <Frame spacing="sm">
            <FramePanel>
              <ul className="flex flex-col gap-2">
                {problems.map((lint) => (
                  <li
                    key={`${lint.name}:${lint.detail ?? lint.title}`}
                    className="flex items-start gap-2 text-sm"
                  >
                    <Badge
                      variant={
                        lint.level === "ERROR"
                          ? "destructive-light"
                          : "warning-light"
                      }
                    >
                      {lint.level === "ERROR" ? "Error" : "Warning"}
                    </Badge>
                    <span className="min-w-0">{lint.detail ?? lint.title}</span>
                  </li>
                ))}
              </ul>
            </FramePanel>
          </Frame>
        )}
      </section>
      <section aria-labelledby="deploy-next" className="flex flex-col gap-2">
        <h3 id="deploy-next" className="text-sm font-medium">
          Next steps
        </h3>
        <p className="text-xs text-muted-foreground">
          Write the config and the wiring into your app, then link it and pull
          the migration, so the next schema diff starts from this one.
        </p>
        <CommandRow label="install" command={install} testId="deploy-install" />
        <CommandRow
          label="link"
          command={`npx supabase link --project-ref ${result.ref}`}
          testId="deploy-link"
        />
        <CommandRow
          label="fetch"
          command="npx supabase migration fetch"
          testId="deploy-fetch"
        />
      </section>
    </div>
  );
}

function Target({
  data,
  named,
  disabled,
  onCreate,
  onDeploy,
}: {
  data: ProjectsResponse;
  named: string | undefined;
  disabled: boolean;
  onCreate: (input: {
    organizationSlug: string;
    name: string;
    region: SmartRegion;
  }) => void;
  onDeploy: (ref: string, confirm: boolean) => void;
}): ReactElement {
  const ids = useId();

  const [tab, setTab] = useState(
    data.projects.length === 0 ? "new" : "existing",
  );

  const [org, setOrg] = useState(data.organizations[0]?.slug ?? "");
  const [name, setName] = useState(() => suggestedProjectName(named));

  const [region, setRegion] = useState<SmartRegion>("americas");
  const [ref, setRef] = useState<string | undefined>(undefined);

  const [status, setStatus] = useState<
    | { readonly state: "loading" }
    | { readonly state: "error"; readonly message: string }
    | { readonly state: "ready"; readonly value: ProjectStatusResponse }
    | undefined
  >(undefined);

  const [confirmed, setConfirmed] = useState(false);

  const pick = async (next: string): Promise<void> => {
    setRef(next);
    setConfirmed(false);
    setStatus({ state: "loading" });

    const outcome = await request<ProjectStatusResponse>(
      `/projects/${encodeURIComponent(next)}`,
    );

    setStatus(
      outcome.ok
        ? { state: "ready", value: outcome.value }
        : { state: "error", message: outcome.error.message },
    );
  };

  const occupied =
    status?.state === "ready" && (status.value.publicTables ?? 0) > 0;

  const canDeployExisting =
    ref !== undefined &&
    status?.state === "ready" &&
    status.value.ready &&
    (!occupied || confirmed);

  if (data.organizations.length === 0) {
    return (
      <Alert variant="warning">
        <TriangleAlertIcon aria-hidden="true" />
        <AlertTitle>No Supabase organization</AlertTitle>
        <AlertDescription>
          Create an organization in the Supabase dashboard first.
        </AlertDescription>
        <AlertAction>
          <a
            href="https://supabase.com/dashboard/new"
            target="_blank"
            rel="noreferrer"
            className={buttonVariants({ variant: "outline", size: "sm" })}
          >
            Open Supabase
          </a>
        </AlertAction>
      </Alert>
    );
  }

  return (
    <Tabs
      value={tab}
      onValueChange={(value) => {
        setTab(String(value));
      }}
      className="gap-4"
    >
      <TabsList aria-label="Deploy target">
        <TabsTrigger value="existing">Existing project</TabsTrigger>
        <TabsTrigger value="new">New project</TabsTrigger>
      </TabsList>
      <TabsContent value="new" className="flex flex-col gap-4">
        <Field>
          <FieldLabel htmlFor={`${ids}-org`}>Organization</FieldLabel>
          <Select
            value={org}
            items={data.organizations.map((each) => ({
              value: each.slug,
              label: each.name,
            }))}
            onValueChange={(next) => {
              if (next !== null) {
                setOrg(next);
              }
            }}
          >
            <SelectTrigger id={`${ids}-org`} size="sm" className="w-full">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {data.organizations.map((each) => (
                <SelectItem key={each.slug} value={each.slug}>
                  {each.name}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </Field>
        <Field>
          <FieldLabel htmlFor={`${ids}-name`}>Project name</FieldLabel>
          <Input
            id={`${ids}-name`}
            value={name}
            maxLength={64}
            onChange={(event) => {
              setName(event.target.value);
            }}
          />
        </Field>
        <Field>
          <FieldLabel htmlFor={`${ids}-region`}>Region</FieldLabel>
          <Select
            value={region}
            items={SMART_REGIONS.map((each) => ({
              value: each,
              label: REGION_LABELS[each],
            }))}
            onValueChange={(next) => {
              if (next !== null) {
                setRegion(next);
              }
            }}
          >
            <SelectTrigger id={`${ids}-region`} size="sm" className="w-full">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {SMART_REGIONS.map((each) => (
                <SelectItem key={each} value={each}>
                  {REGION_LABELS[each]}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          <FieldDescription>
            Supabase picks a region with capacity in this area. The project
            starts on your organization&apos;s plan.
          </FieldDescription>
        </Field>
        <Button
          type="button"
          className="self-start"
          disabled={disabled || org === "" || name.trim() === ""}
          onClick={() => {
            onCreate({ organizationSlug: org, name: name.trim(), region });
          }}
        >
          <UploadIcon aria-hidden="true" />
          Create and deploy
        </Button>
      </TabsContent>
      <TabsContent value="existing" className="flex flex-col gap-4">
        {data.projects.length === 0 ? (
          <div className="flex flex-col items-start gap-3 rounded-lg border border-dashed border-border p-4">
            <p className="text-sm text-muted-foreground">
              No projects in your organizations yet.
            </p>
            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={() => {
                setTab("new");
              }}
            >
              Create a new project
            </Button>
          </div>
        ) : (
          <>
            <Field>
              <FieldLabel htmlFor={`${ids}-project`}>Project</FieldLabel>
              <Select
                value={ref ?? null}
                items={data.projects.map((each) => ({
                  value: each.ref,
                  label: each.name,
                }))}
                onValueChange={(next) => {
                  if (next !== null) {
                    void pick(next);
                  }
                }}
              >
                <SelectTrigger
                  id={`${ids}-project`}
                  size="sm"
                  className="w-full"
                >
                  <SelectValue placeholder="Pick a project" />
                </SelectTrigger>
                <SelectContent>
                  {data.projects.map((each: SupabaseProject) => (
                    <SelectItem key={each.ref} value={each.ref}>
                      {each.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
            {status?.state === "loading" ? (
              <Skeleton className="h-16 w-full" />
            ) : null}
            {status?.state === "error" ? (
              <Alert variant="destructive">
                <CircleAlertIcon aria-hidden="true" />
                <AlertTitle>The project can&apos;t be read</AlertTitle>
                <AlertDescription>{status.message}</AlertDescription>
                <AlertAction>
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => {
                      if (ref !== undefined) {
                        void pick(ref);
                      }
                    }}
                  >
                    <RotateCwIcon aria-hidden="true" />
                    Retry
                  </Button>
                </AlertAction>
              </Alert>
            ) : null}
            {status?.state === "ready" && !status.value.ready ? (
              <Alert variant="warning">
                <TriangleAlertIcon aria-hidden="true" />
                <AlertTitle>The database isn&apos;t running</AlertTitle>
                <AlertDescription>
                  The project is {status.value.project.status.toLowerCase()}.
                  Restore or wait for it in the dashboard, then pick it again.
                </AlertDescription>
              </Alert>
            ) : null}
            {occupied ? (
              <Alert variant="warning">
                <TriangleAlertIcon aria-hidden="true" />
                <AlertTitle>
                  The public schema has {status.value.publicTables} tables
                </AlertTitle>
                <AlertDescription>
                  The modules create their tables with{" "}
                  <code className="font-mono">if not exists</code> and replace
                  their own functions, policies and triggers. A table of yours
                  with the same name keeps its columns.
                </AlertDescription>
              </Alert>
            ) : null}
            {occupied ? (
              <Field orientation="horizontal">
                <Checkbox
                  id={`${ids}-confirm`}
                  checked={confirmed}
                  onCheckedChange={(checked) => {
                    setConfirmed(checked);
                  }}
                />
                <FieldLabel htmlFor={`${ids}-confirm`}>
                  Deploy into this project anyway
                </FieldLabel>
              </Field>
            ) : null}
            <Button
              type="button"
              className="self-start"
              disabled={disabled || !canDeployExisting}
              onClick={() => {
                if (ref !== undefined) {
                  onDeploy(ref, confirmed);
                }
              }}
            >
              <UploadIcon aria-hidden="true" />
              Deploy
            </Button>
          </>
        )}
      </TabsContent>
    </Tabs>
  );
}

function DeployBody({
  attempt,
  connectFailed,
  returnTo,
  named,
  phase,
  onRetry,
  onCreate,
  onDeploy,
}: {
  attempt: number;
  connectFailed: boolean;
  returnTo: string;
  named: string | undefined;
  phase: Phase;
  onRetry: () => void;
  onCreate: (input: {
    organizationSlug: string;
    name: string;
    region: SmartRegion;
  }) => void;
  onDeploy: (ref: string, confirm: boolean) => void;
}): ReactElement {
  const outcome = use(projectsFor(attempt));

  if (!outcome.ok && outcome.error.error === "connect") {
    return <ConnectStep failed={connectFailed} returnTo={returnTo} />;
  }

  if (!outcome.ok) {
    return (
      <Alert variant="destructive">
        <CircleAlertIcon aria-hidden="true" />
        <AlertTitle>Your projects can&apos;t be loaded</AlertTitle>
        <AlertDescription>{outcome.error.message}</AlertDescription>
        <AlertAction>
          <Button variant="outline" size="sm" onClick={onRetry}>
            <RotateCwIcon aria-hidden="true" />
            Retry
          </Button>
        </AlertAction>
      </Alert>
    );
  }

  const busy = phase.step !== "idle" && phase.step !== "failed";

  return (
    <div className="flex flex-col gap-4">
      <Target
        data={outcome.value}
        named={named}
        disabled={busy}
        onCreate={onCreate}
        onDeploy={onDeploy}
      />
      <Button
        type="button"
        variant="ghost"
        size="sm"
        className="self-start"
        disabled={busy}
        onClick={() => {
          void request<null>("/disconnect", { method: "POST" }).then(onRetry);
        }}
      >
        Use another Supabase account
      </Button>
    </div>
  );
}

/**
 * Deploys the preset's SQL to a project in the visitor's own Supabase
 * account: connect through Supabase's OAuth consent screen, pick a project
 * or create one, then apply the migrations as one migration. `blocker`
 * says why this preset can't be deployed, and `connectFailed` that the
 * last consent screen didn't connect.
 */
export function DeployDialog({
  open,
  onOpenChange,
  code,
  designCode,
  resolved,
  named,
  pkg,
  blocker,
  connectFailed,
  returnTo,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  code: string;
  designCode: string;
  resolved: ResolvedPreset;
  named: string | undefined;
  pkg: string | undefined;
  blocker: string | undefined;
  connectFailed: boolean;
  /** The `/create` URL for these choices, which the consent screen returns to. */
  returnTo: string;
}): ReactElement {
  const [attempt, retry] = useReducer((count: number) => count + 1, 0);
  const [phase, setPhase] = useState<Phase>({ step: "idle" });
  const run = useRef(0);

  const install = commandFor(
    withPackage(designInstallCommand(resolved, designCode), pkg),
    "pnpm",
  );

  const deploy = async (
    ref: string,
    confirm: boolean,
    password: string | undefined,
    token: number,
  ): Promise<void> => {
    setPhase({ step: "deploying", ref, password });

    const outcome = await request<DeployResponse>("/deploy", {
      method: "POST",
      body: JSON.stringify({
        ref,
        preset: code,
        design: designCode,
        confirm,
      }),
    });

    if (run.current !== token) {
      return;
    }

    setPhase(
      outcome.ok
        ? { step: "done", result: outcome.value, password }
        : { step: "failed", message: outcome.error.message, password },
    );
  };

  const create = async (input: {
    organizationSlug: string;
    name: string;
    region: SmartRegion;
  }): Promise<void> => {
    const token = run.current + 1;
    run.current = token;
    setPhase({ step: "creating" });

    const created = await request<CreatedProjectResponse>("/projects", {
      method: "POST",
      body: JSON.stringify(input),
    });

    if (run.current !== token) {
      return;
    }

    if (!created.ok) {
      setPhase({
        step: "failed",
        message: created.error.message,
        password: undefined,
      });

      return;
    }

    const { project, dbPassword } = created.value;
    setPhase({ step: "starting", ref: project.ref, password: dbPassword });

    for (let poll = 0; poll < START_POLLS; poll += 1) {
      await sleep(POLL_MS);

      if (run.current !== token) {
        return;
      }

      const status = await request<ProjectStatusResponse>(
        `/projects/${encodeURIComponent(project.ref)}`,
      );

      if (status.ok && status.value.ready) {
        await deploy(project.ref, false, dbPassword, token);

        return;
      }
    }

    setPhase({
      step: "failed",
      message: `${project.name} is still starting. Deploy to it from Existing project once it is up.`,
      password: dbPassword,
    });
  };

  const close = (next: boolean): void => {
    if (!next) {
      run.current += 1;

      if (phase.step === "done" || phase.step === "failed") {
        setPhase({ step: "idle" });
      }
    }

    onOpenChange(next);
  };

  return (
    <Dialog open={open} onOpenChange={close}>
      <DialogContent className="max-h-[calc(100svh-2rem)] grid-cols-[minmax(0,1fr)] overflow-y-auto sm:max-w-xl">
        <DialogHeader>
          <DialogTitle>Deploy to Supabase</DialogTitle>
          <DialogDescription>
            Apply the {resolved.blocks.length} blocks&apos; SQL to a project in
            your Supabase account as one migration.
          </DialogDescription>
        </DialogHeader>

        {blocker === undefined ? (
          <div className="flex min-w-0 flex-col gap-4">
            {phase.step === "done" ? (
              <DeployResult
                result={phase.result}
                password={phase.password}
                install={install}
              />
            ) : (
              <>
                <Suspense fallback={<ProjectsSkeleton />}>
                  <DeployBody
                    attempt={attempt}
                    connectFailed={connectFailed}
                    returnTo={returnTo}
                    named={named}
                    phase={phase}
                    onRetry={() => {
                      projectRequests.delete(attempt);
                      retry();
                    }}
                    onCreate={(input) => {
                      void create(input);
                    }}
                    onDeploy={(ref, confirm) => {
                      const token = run.current + 1;
                      run.current = token;
                      void deploy(ref, confirm, undefined, token);
                    }}
                  />
                </Suspense>
                <PhaseStatus phase={phase} />
                {phase.step === "failed" ? (
                  <Alert variant="destructive">
                    <CircleAlertIcon aria-hidden="true" />
                    <AlertTitle>The deploy didn&apos;t finish</AlertTitle>
                    <AlertDescription>{phase.message}</AlertDescription>
                  </Alert>
                ) : null}
                {phase.step === "failed" && phase.password !== undefined ? (
                  <PasswordRow password={phase.password} />
                ) : null}
              </>
            )}
          </div>
        ) : (
          <Alert variant="info">
            <CircleAlertIcon aria-hidden="true" />
            <AlertTitle>This preset deploys with the CLI</AlertTitle>
            <AlertDescription>{blocker}</AlertDescription>
          </Alert>
        )}
      </DialogContent>
    </Dialog>
  );
}
