"use client";

import type { ReactElement } from "react";

import {
  CircleAlertIcon,
  FileCodeIcon,
  LinkIcon,
  RotateCwIcon,
} from "lucide-react";
import { Suspense, use, useId, useReducer } from "react";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { LinkButton } from "@/components/site/link-button";
import { Button } from "@/components/ui/button";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Field, FieldDescription, FieldLabel } from "@/components/ui/field";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import { Switch } from "@/components/ui/switch";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  type AppScope,
  isAppTable,
  ON_DELETE_ACTIONS,
  type OnDeleteAction,
  setColumn,
  updateTable,
} from "@/lib/design";
import {
  type SchemaData,
  type SchemaTable,
  tableStatements,
} from "@/lib/schema";

import type { InspectorTab } from "./schema-nodes";

import { useDesign } from "./design-provider";
import {
  ColumnsTab,
  OverviewTab,
  type InspectorPreset,
} from "./inspector-columns";
import {
  forgetMigrations,
  migrationsFor,
  MigrationsSkeleton,
} from "./migrations-panel";
import { TableKeyFields } from "./table-keys";

const TABS: readonly {
  readonly value: InspectorTab;
  readonly label: string;
}[] = [
  { value: "overview", label: "Overview" },
  { value: "columns", label: "Columns" },
  { value: "relations", label: "Relations" },
  { value: "options", label: "Options" },
  { value: "sql", label: "SQL" },
];

function isTab(value: unknown): value is InspectorTab {
  return TABS.some((tab) => tab.value === value);
}

function isOnDelete(value: unknown): value is OnDeleteAction {
  return ON_DELETE_ACTIONS.some((action) => action === value);
}

const SCOPES: readonly { readonly value: AppScope; readonly label: string }[] =
  [
    { value: "inherit", label: "Follow the preset" },
    { value: "user", label: "Per user" },
    { value: "none", label: "Not scoped" },
  ];

function isScope(value: unknown): value is AppScope {
  return SCOPES.some((scope) => scope.value === value);
}

function RelationButton({
  label,
  id,
  onOpen,
}: {
  label: string;
  id: string;
  onOpen: (id: string, tab?: InspectorTab) => void;
}): ReactElement {
  return (
    <button
      type="button"
      className="font-mono text-primary underline-offset-4 transition-colors hover:underline"
      onClick={() => {
        onOpen(id, "relations");
      }}
    >
      {label}
    </button>
  );
}

function RelationsTab({
  table,
  data,
  onOpen,
}: {
  table: SchemaTable;
  data: SchemaData;
  onOpen: (id: string, tab?: InspectorTab) => void;
}): ReactElement {
  const { state, actions } = useDesign();
  const known = new Set(data.tables.map((each) => each.id));

  const config = isAppTable(table)
    ? state.design.appTables?.[table.name]
    : undefined;

  const outgoing = table.foreignKeys.map((key) => ({
    column: key.columns.join(", "),
    to: `${key.target.schema}.${key.target.table}`,
  }));

  const incoming = data.tables.flatMap((each) =>
    each.foreignKeys
      .filter((key) => `${key.target.schema}.${key.target.table}` === table.id)
      .map((key) => ({
        from: each.id,
        label: `${each.name}.${key.columns.join(", ")}`,
      })),
  );

  const softOut = data.softRefs.filter((ref) => ref.from === table.id);
  const softIn = data.softRefs.filter((ref) => ref.to === table.id);

  if (
    outgoing.length + incoming.length + softOut.length + softIn.length ===
    0
  ) {
    return (
      <Empty className="border border-dashed p-6">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <LinkIcon aria-hidden="true" />
          </EmptyMedia>
          <EmptyTitle>No relations</EmptyTitle>
          <EmptyDescription>
            {isAppTable(table)
              ? "Drag the handle on the table onto another table to add a foreign key."
              : "No table references this one, and it references none."}
          </EmptyDescription>
        </EmptyHeader>
      </Empty>
    );
  }

  return (
    <div className="flex flex-col gap-6">
      {outgoing.length === 0 ? null : (
        <section className="flex flex-col gap-2">
          <h3 className="text-sm font-medium">References</h3>
          <ul className="flex flex-col divide-y divide-border rounded-lg border border-border">
            {outgoing.map((relation) => {
              const column = config?.columns?.[relation.column];

              return (
                <li
                  key={relation.column}
                  className="flex flex-wrap items-center gap-2 px-3 py-2 text-sm"
                >
                  <span className="font-mono">{relation.column}</span>
                  <span className="text-muted-foreground">to</span>
                  {known.has(relation.to) ? (
                    <RelationButton
                      label={relation.to}
                      id={relation.to}
                      onOpen={onOpen}
                    />
                  ) : (
                    <span className="font-mono">{relation.to}</span>
                  )}
                  {column?.references === undefined ? null : (
                    <div className="ml-auto w-36">
                      <Select
                        value={column.references.onDelete ?? "no action"}
                        onValueChange={(next) => {
                          if (
                            isOnDelete(next) &&
                            column.references !== undefined
                          ) {
                            actions.apply(
                              setColumn(
                                state.design,
                                table.name,
                                relation.column,
                                {
                                  ...column,
                                  references: {
                                    ...column.references,
                                    onDelete: next,
                                  },
                                },
                              ),
                            );
                          }
                        }}
                      >
                        <SelectTrigger
                          size="sm"
                          className="w-full"
                          aria-label="On delete"
                        >
                          <SelectValue>
                            {(value: string) => `on delete ${value}`}
                          </SelectValue>
                        </SelectTrigger>
                        <SelectContent>
                          {ON_DELETE_ACTIONS.map((action) => (
                            <SelectItem key={action} value={action}>
                              {action}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
                  )}
                </li>
              );
            })}
          </ul>
        </section>
      )}
      {incoming.length === 0 ? null : (
        <section className="flex flex-col gap-2">
          <h3 className="text-sm font-medium">Referenced by</h3>
          <ul className="flex flex-col divide-y divide-border rounded-lg border border-border">
            {incoming.map((relation) => (
              <li key={relation.label} className="px-3 py-2 text-sm">
                <RelationButton
                  label={relation.label}
                  id={relation.from}
                  onOpen={onOpen}
                />
              </li>
            ))}
          </ul>
        </section>
      )}
      {softOut.length + softIn.length === 0 ? null : (
        <section className="flex flex-col gap-2">
          <h3 className="text-sm font-medium">Soft references</h3>
          <p className="text-xs text-muted-foreground">
            Plain columns without a foreign key, so the rows outlive a delete on
            the other side.
          </p>
          <ul className="flex flex-col divide-y divide-border rounded-lg border border-border">
            {softOut.map((ref) => (
              <li
                key={`out-${ref.column}`}
                className="flex flex-wrap items-center gap-2 px-3 py-2 text-sm"
              >
                <span className="font-mono">{ref.column}</span>
                <span className="text-muted-foreground">to</span>
                {ref.to === null ? (
                  <span className="text-muted-foreground">any table</span>
                ) : known.has(ref.to) ? (
                  <RelationButton label={ref.to} id={ref.to} onOpen={onOpen} />
                ) : (
                  <span className="font-mono">{ref.to}</span>
                )}
              </li>
            ))}
            {softIn.map((ref) => (
              <li
                key={`in-${ref.from}.${ref.column}`}
                className="px-3 py-2 text-sm"
              >
                <RelationButton
                  label={`${ref.from}.${ref.column}`}
                  id={ref.from}
                  onOpen={onOpen}
                />
              </li>
            ))}
          </ul>
        </section>
      )}
    </div>
  );
}

function OptionsTab({
  table,
  preset,
}: {
  table: SchemaTable;
  preset: InspectorPreset;
}): ReactElement {
  const { state, actions } = useDesign();
  const id = useId();

  const config = isAppTable(table)
    ? state.design.appTables?.[table.name]
    : undefined;

  if (config === undefined) {
    return (
      <div className="flex flex-col gap-3 text-sm">
        <p className="text-muted-foreground">
          The {table.module} block owns this table. Its options are in the
          Customize panel, and its page lists every option.
        </p>
        <div>
          <LinkButton
            href={`/blocks/${table.module}`}
            variant="outline"
            size="sm"
          >
            Open the {table.module} block
          </LinkButton>
        </div>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-6">
      <Field>
        <FieldLabel htmlFor={`${id}-scope`}>Rows belong to</FieldLabel>
        <Select
          value={config.scope ?? "inherit"}
          onValueChange={(next) => {
            if (isScope(next)) {
              actions.apply(
                updateTable(state.design, table.name, { scope: next }),
              );
            }
          }}
        >
          <SelectTrigger id={`${id}-scope`} size="sm" className="w-full">
            <SelectValue>
              {(value: string) =>
                SCOPES.find((scope) => scope.value === value)?.label ?? value
              }
            </SelectValue>
          </SelectTrigger>
          <SelectContent>
            {SCOPES.map((scope) => (
              <SelectItem key={scope.value} value={scope.value}>
                {scope.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <FieldDescription>
          {preset.scope === "tenant"
            ? `Following the preset adds ${preset.tenantName}_id and scopes the policies by ${preset.tenantName}.`
            : "Following the preset adds user_id and scopes the policies by user."}
        </FieldDescription>
      </Field>
      <Field orientation="horizontal">
        <Switch
          id={`${id}-timestamps`}
          checked={config.timestamps !== false}
          onCheckedChange={(checked) => {
            actions.apply(
              updateTable(state.design, table.name, { timestamps: checked }),
            );
          }}
        />
        <FieldLabel htmlFor={`${id}-timestamps`}>
          created_at and updated_at
        </FieldLabel>
      </Field>
      <TableKeyFields table={table} />
    </div>
  );
}

function SqlStatements({
  table,
  code,
  designCode,
  onRetry,
}: {
  table: SchemaTable;
  code: string;
  designCode: string;
  onRetry: () => void;
}): ReactElement {
  const state = use(migrationsFor(code, designCode));

  if (state.status === "error") {
    return (
      <Alert variant="destructive">
        <CircleAlertIcon aria-hidden="true" />
        <AlertTitle>The SQL could not be rendered</AlertTitle>
        <AlertDescription>{state.message}</AlertDescription>
        <AlertAction>
          <Button
            variant="outline"
            size="sm"
            onClick={() => {
              forgetMigrations(code, designCode);
              onRetry();
            }}
          >
            <RotateCwIcon aria-hidden="true" />
            Retry
          </Button>
        </AlertAction>
      </Alert>
    );
  }

  const statements = tableStatements(state.files, table.id);

  if (statements.length === 0) {
    return (
      <Empty className="border border-dashed p-6">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <FileCodeIcon aria-hidden="true" />
          </EmptyMedia>
          <EmptyTitle>No SQL for this table yet</EmptyTitle>
          <EmptyDescription>
            The preview renders the table once the design is saved in the link.
            Retry after the next edit.
          </EmptyDescription>
        </EmptyHeader>
      </Empty>
    );
  }

  return (
    <pre className="overflow-auto rounded-lg border border-border bg-muted/30 p-4 font-mono text-xs leading-6">
      <code>{statements.join("\n\n")}</code>
    </pre>
  );
}

function SqlTab(props: {
  table: SchemaTable;
  code: string;
  designCode: string;
}): ReactElement {
  const [attempt, retry] = useReducer((count: number) => count + 1, 0);

  return (
    <Suspense fallback={<MigrationsSkeleton />}>
      <SqlStatements key={attempt} {...props} onRetry={retry} />
    </Suspense>
  );
}

/**
 * The selected table: its columns, relations, options and SQL. App tables
 * and the block tables that take extra columns are edited here; everything
 * else is read-only. Full width below the large breakpoint.
 */
export function TableInspector({
  table,
  tab,
  onTab,
  onClose,
  onOpen,
  onDelete,
  code,
  designCode,
  data,
  preset,
}: {
  table: SchemaTable | undefined;
  tab: InspectorTab;
  onTab: (tab: InspectorTab) => void;
  onClose: () => void;
  onOpen: (id: string, tab?: InspectorTab) => void;
  onDelete: (id: string) => void;
  code: string;
  designCode: string;
  data: SchemaData;
  preset: InspectorPreset;
}): ReactElement {
  return (
    <Sheet
      open={table !== undefined}
      onOpenChange={(open) => {
        if (!open) {
          onClose();
        }
      }}
    >
      <SheetContent
        side="right"
        className="w-full gap-0 p-0 data-[side=right]:w-full data-[side=right]:sm:max-w-none lg:data-[side=right]:w-[34rem]"
      >
        {table === undefined ? null : (
          <>
            <SheetHeader className="border-b border-border">
              <SheetTitle className="font-mono">{table.name}</SheetTitle>
              <SheetDescription>
                {isAppTable(table)
                  ? "An app table you designed."
                  : `From the ${table.module} block.`}
              </SheetDescription>
            </SheetHeader>
            <Tabs
              value={tab}
              onValueChange={(value) => {
                if (isTab(value)) {
                  onTab(value);
                }
              }}
              className="min-h-0 flex-1 gap-0"
            >
              <div className="overflow-x-auto border-b border-border px-4 py-2">
                <TabsList>
                  {TABS.map((each) => (
                    <TabsTrigger key={each.value} value={each.value}>
                      {each.label}
                    </TabsTrigger>
                  ))}
                </TabsList>
              </div>
              <div className="min-h-0 flex-1 overflow-y-auto p-4">
                <TabsContent value="overview">
                  <OverviewTab
                    table={table}
                    data={data}
                    preset={preset}
                    onOpen={onOpen}
                    onDelete={onDelete}
                  />
                </TabsContent>
                <TabsContent value="columns">
                  <ColumnsTab table={table} data={data} preset={preset} />
                </TabsContent>
                <TabsContent value="relations">
                  <RelationsTab table={table} data={data} onOpen={onOpen} />
                </TabsContent>
                <TabsContent value="options">
                  <OptionsTab table={table} preset={preset} />
                </TabsContent>
                <TabsContent value="sql">
                  <SqlTab table={table} code={code} designCode={designCode} />
                </TabsContent>
              </div>
            </Tabs>
          </>
        )}
      </SheetContent>
    </Sheet>
  );
}
