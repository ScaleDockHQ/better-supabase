"use client";

import type {
  CellContext,
  ColumnDef,
  RowSelectionState,
} from "@tanstack/react-table";

import { useTable } from "@tanstack/react-table";
import { useAction } from "better-supabase/react";
import { BookmarkIcon, SearchIcon, Trash2Icon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useState, useTransition } from "react";
import { toast } from "sonner";
import * as v from "valibot";

import type { DataGridFeatures } from "@/components/reui/data-grid/data-grid";
import type {
  FilterField,
  FilterQuery,
} from "@/components/reui/filters/filters";

import {
  DataGrid,
  DataGridContainer,
  dataGridFeatures,
} from "@/components/reui/data-grid/data-grid";
import { DataGridScrollArea } from "@/components/reui/data-grid/data-grid-scroll-area";
import {
  DataGridTable,
  DataGridTableRowSelect,
  DataGridTableRowSelectAll,
} from "@/components/reui/data-grid/data-grid-table";
import {
  Filters,
  createFilterQuery,
  createFilterRule,
  flattenFilterConditions,
} from "@/components/reui/filters/filters";
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
import { Field, FieldError, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Link, usePathname, useRouter, withSearch } from "@/i18n/navigation";
import { useErrorMessage } from "@/lib/use-error-message";

import type {
  MemberOption,
  ProjectOption,
  TaskQuery,
  TaskRow,
  TaskViewOption,
} from "../project-types";

import {
  deleteTaskView,
  runTaskBulkAction,
  saveTaskView,
  setTaskField,
} from "../project-actions";
import { TASK_STATUSES, taskSearch } from "../project-types";
import { useStatusLabel } from "../use-task-labels";
import { TaskStatusBadge } from "./task-status-badge";

// #region recipe:record-grid
const STATUS_FIELD = "status";
const PROJECT_FIELD = "project";
const ONLY_IS = [{ value: "is", label: "is" }];

/** The URL's status and project filters as a ReUI filter query. */
function toFilterQuery(query: TaskQuery): FilterQuery<string> {
  return createFilterQuery([
    ...(query.status === null
      ? []
      : [
          createFilterRule({
            id: STATUS_FIELD,
            path: [STATUS_FIELD],
            operator: "is",
            value: query.status,
          }),
        ]),
    ...(query.projectId === null
      ? []
      : [
          createFilterRule({
            id: PROJECT_FIELD,
            path: [PROJECT_FIELD],
            operator: "is",
            value: query.projectId,
          }),
        ]),
  ]);
}

/** The one value a filter rule holds, or null once it is cleared. */
function valueOf(query: FilterQuery<string>, field: string): string | null {
  const condition = flattenFilterConditions(query).find(
    (each) => each.field === field,
  );

  const value = v.safeParse(v.string(), condition?.values[0]);

  return value.success ? value.output : null;
}

/**
 * The search, the filters and the saved views every task screen shares. They
 * live in the URL, so a saved view is the screen plus its search string.
 */
export function TaskToolbar({
  query,
  projects,
  views,
  canSaveViews,
}: {
  query: TaskQuery;
  projects: readonly ProjectOption[];
  views: readonly TaskViewOption[];
  canSaveViews: boolean;
}) {
  const t = useExtracted("projects");
  const router = useRouter();
  const pathname = usePathname();
  const statusLabel = useStatusLabel();
  const errorMessage = useErrorMessage();
  const [navigating, startTransition] = useTransition();
  const [search, setSearch] = useState(query.q);

  const removeView = useAction(deleteTaskView, {
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  const go = (next: TaskQuery) => {
    startTransition(() => {
      router.replace(withSearch(pathname, taskSearch(next)));
    });
  };

  const fields: FilterField<string>[] = [
    {
      id: STATUS_FIELD,
      label: t("Status"),
      type: "select",
      operators: ONLY_IS,
      options: TASK_STATUSES.map((status) => ({
        value: status,
        label: statusLabel(status),
      })),
    },
    {
      id: PROJECT_FIELD,
      label: t("Project"),
      type: "select",
      operators: ONLY_IS,
      options: projects.map((project) => ({
        value: project.id,
        label: project.name,
      })),
    },
  ];

  const activeView = views.find(
    (view) => taskSearch(view.query) === taskSearch(query),
  );

  return (
    <div className="flex flex-wrap items-center gap-2">
      <form
        className="flex items-center gap-2"
        onSubmit={(event) => {
          event.preventDefault();
          go({ ...query, q: search.trim() });
        }}
      >
        <Input
          type="search"
          className="w-56"
          value={search}
          placeholder={t("Search tasks")}
          aria-label={t("Search tasks")}
          onChange={(event) => {
            setSearch(event.target.value);
          }}
        />
        <Button
          type="submit"
          size="icon-sm"
          variant="outline"
          aria-label={t("Search")}
          disabled={navigating}
        >
          <SearchIcon />
        </Button>
      </form>
      <Filters
        size="sm"
        fields={fields}
        query={toFilterQuery(query)}
        showClear
        onQueryChange={(next) => {
          const status = TASK_STATUSES.find(
            (each) => each === valueOf(next, STATUS_FIELD),
          );

          go({
            ...query,
            status: status ?? null,
            projectId: valueOf(next, PROJECT_FIELD),
          });
        }}
      />
      <div className="ml-auto flex items-center gap-2">
        {views.length === 0 ? null : (
          <Select
            value={activeView?.id ?? null}
            items={views.map((view) => ({ value: view.id, label: view.name }))}
            onValueChange={(value) => {
              const view = views.find((each) => each.id === value);

              if (view) {
                setSearch(view.query.q);
                go(view.query);
              }
            }}
          >
            <SelectTrigger
              size="sm"
              className="w-44"
              aria-label={t("Saved views")}
            >
              <SelectValue placeholder={t("Saved views")} />
            </SelectTrigger>
            <SelectContent>
              {views.map((view) => (
                <SelectItem key={view.id} value={view.id}>
                  {view.name}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        )}
        {activeView ? (
          <Button
            size="icon-sm"
            variant="outline"
            aria-label={t("Delete view {name}", { name: activeView.name })}
            disabled={removeView.pending}
            onClick={() => {
              void removeView.run({ id: activeView.id });
            }}
          >
            <Trash2Icon />
          </Button>
        ) : null}
        {canSaveViews ? <SaveTaskViewDialog query={query} /> : null}
      </div>
    </div>
  );
}

function SaveTaskViewDialog({ query }: { query: TaskQuery }) {
  const t = useExtracted("projects");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);
  const [name, setName] = useState("");
  const save = useAction(saveTaskView);
  const error = save.error === undefined ? null : errorMessage(save.error);

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger render={<Button size="sm" variant="outline" />}>
        <BookmarkIcon />
        {t("Save view")}
      </DialogTrigger>
      <DialogContent>
        <form
          className="grid gap-6"
          onSubmit={(event) => {
            event.preventDefault();
            void save.run({ name, ...query }).then((result) => {
              if (result.ok) {
                toast.success(t("View saved"));
                setName("");
                setOpen(false);
              }

              return result;
            });
          }}
        >
          <DialogHeader>
            <DialogTitle>{t("Save view")}</DialogTitle>
            <DialogDescription>
              {t("Keeps the screen, the search and the filters.")}
            </DialogDescription>
          </DialogHeader>
          <Field data-invalid={error ? true : undefined}>
            <FieldLabel htmlFor={`${fieldId}-name`}>{t("Name")}</FieldLabel>
            <Input
              id={`${fieldId}-name`}
              value={name}
              required
              maxLength={80}
              autoComplete="off"
              onChange={(event) => {
                setName(event.target.value);
              }}
            />
            {error ? <FieldError>{error}</FieldError> : null}
          </Field>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={save.pending}>
              {t("Save")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

const UNASSIGNED = "unassigned";

type SetField = "due_on" | "assignee_id";

/**
 * Sets one field on the selected tasks through the typed repository. An empty
 * value clears the field.
 */
function SetFieldDialog({
  ids,
  members,
  onDone,
}: {
  ids: readonly string[];
  members: readonly MemberOption[];
  onDone: () => void;
}) {
  const t = useExtracted("projects");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);
  const [field, setField] = useState<SetField>("due_on");
  const [dueOn, setDueOn] = useState("");
  const [assignee, setAssignee] = useState(UNASSIGNED);

  const set = useAction(setTaskField, {
    onSuccess: (count) => {
      toast.success(
        t("{count, plural, one {# task} other {# tasks}} changed", { count }),
      );
      setOpen(false);
      onDone();
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  const fields = [
    { value: "due_on", label: t("Due date") },
    { value: "assignee_id", label: t("Assignee") },
  ] as const satisfies readonly { value: SetField; label: string }[];

  const people = [
    { value: UNASSIGNED, label: t("Unassigned") },
    ...members.map((member) => ({ value: member.userId, label: member.name })),
  ];

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger render={<Button size="sm" variant="outline" />}>
        {t("Set field")}
      </DialogTrigger>
      <DialogContent>
        <form
          className="grid gap-6"
          onSubmit={(event) => {
            event.preventDefault();
            void set.run({
              ids: [...ids],
              values:
                field === "due_on"
                  ? { due_on: dueOn === "" ? null : dueOn }
                  : { assignee_id: assignee === UNASSIGNED ? null : assignee },
            });
          }}
        >
          <DialogHeader>
            <DialogTitle>
              {t(
                "Set a field on {count, plural, one {# task} other {# tasks}}",
                { count: ids.length },
              )}
            </DialogTitle>
            <DialogDescription>
              {t("Leave the value empty to clear the field.")}
            </DialogDescription>
          </DialogHeader>
          <div className="grid gap-4">
            <Field>
              <FieldLabel htmlFor={`${fieldId}-field`}>{t("Field")}</FieldLabel>
              <Select
                value={field}
                items={fields}
                onValueChange={(value) => {
                  const picked = fields.find((each) => each.value === value);

                  if (picked) {
                    setField(picked.value);
                  }
                }}
              >
                <SelectTrigger id={`${fieldId}-field`} className="w-full">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {fields.map((each) => (
                    <SelectItem key={each.value} value={each.value}>
                      {each.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
            {field === "due_on" ? (
              <Field>
                <FieldLabel htmlFor={`${fieldId}-due`}>
                  {t("Due date")}
                </FieldLabel>
                <Input
                  id={`${fieldId}-due`}
                  type="date"
                  value={dueOn}
                  onChange={(event) => {
                    setDueOn(event.target.value);
                  }}
                />
              </Field>
            ) : (
              <Field>
                <FieldLabel htmlFor={`${fieldId}-assignee`}>
                  {t("Assignee")}
                </FieldLabel>
                <Select
                  value={assignee}
                  items={people}
                  onValueChange={(value) => {
                    const person = people.find((each) => each.value === value);

                    if (person) {
                      setAssignee(person.value);
                    }
                  }}
                >
                  <SelectTrigger id={`${fieldId}-assignee`} className="w-full">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {people.map((person) => (
                      <SelectItem key={person.value} value={person.value}>
                        {person.label}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </Field>
            )}
          </div>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={set.pending}>
              {t("Apply")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

type GridRow = TaskRow & {
  readonly projectName: string;
  readonly assigneeName: string;
};

type GridCell = CellContext<DataGridFeatures, GridRow>;

const SELECT_COLUMN = {
  id: "select",
  header: () => <DataGridTableRowSelectAll />,
  cell: ({ row }) => <DataGridTableRowSelect row={row} />,
  size: 40,
} satisfies ColumnDef<DataGridFeatures, GridRow>;

function TitleCell({ row }: GridCell) {
  return (
    <Link
      href={`/projects/${row.original.projectId}`}
      className="font-medium hover:underline"
    >
      {row.original.title}
    </Link>
  );
}

function StatusCell({ row }: GridCell) {
  return <TaskStatusBadge status={row.original.status} />;
}

/**
 * Tasks in a ReUI data grid. The checkboxes feed a bulk bar that sets the
 * status of the selected rows, sets another field through the bulk block, or
 * deletes them in one statement.
 */
export function TaskGrid({
  rows,
  projects,
  members,
  canWrite,
}: {
  rows: readonly TaskRow[];
  projects: readonly ProjectOption[];
  members: readonly MemberOption[];
  canWrite: boolean;
}) {
  const t = useExtracted("projects");
  const statusLabel = useStatusLabel();
  const errorMessage = useErrorMessage();
  const [selection, setSelection] = useState<RowSelectionState>({});
  const projectName = new Map(projects.map((each) => [each.id, each.name]));
  const memberName = new Map(members.map((each) => [each.userId, each.name]));

  const bulk = useAction(runTaskBulkAction, {
    onSuccess: ({ count }) => {
      toast.success(
        t("{count, plural, one {# task} other {# tasks}} changed", { count }),
      );
      setSelection({});
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  const columns: ColumnDef<DataGridFeatures, GridRow>[] = [
    ...(canWrite ? [SELECT_COLUMN] : []),
    { accessorKey: "title", header: t("Title"), cell: TitleCell, size: 280 },
    { accessorKey: "status", header: t("Status"), cell: StatusCell, size: 120 },
    { accessorKey: "projectName", header: t("Project"), size: 180 },
    { accessorKey: "assigneeName", header: t("Assignee"), size: 160 },
    { accessorKey: "dueOn", header: t("Due"), size: 120 },
  ];

  const data = rows.map((row) => ({
    ...row,
    projectName: projectName.get(row.projectId) ?? "",
    assigneeName:
      row.assigneeId === null
        ? t("Unassigned")
        : (memberName.get(row.assigneeId) ?? ""),
  }));

  const table = useTable({
    features: dataGridFeatures,
    columns,
    data,
    getRowId: (row) => row.id,
    state: { rowSelection: selection },
    enableRowSelection: canWrite,
    onRowSelectionChange: setSelection,
  });

  const ids = rows.filter((row) => selection[row.id]).map((row) => row.id);

  return (
    <div className="flex flex-col gap-3" data-recipe="record-grid">
      {ids.length > 0 ? (
        <div className="flex flex-wrap items-center gap-2 rounded-lg border bg-muted/50 p-2">
          <span className="text-sm">
            {t("{count, plural, one {# selected} other {# selected}}", {
              count: ids.length,
            })}
          </span>
          {TASK_STATUSES.map((status) => (
            <Button
              key={status}
              size="sm"
              variant="outline"
              disabled={bulk.pending}
              onClick={() => {
                void bulk.run({ kind: "status", ids, status });
              }}
            >
              {t("Mark {status}", { status: statusLabel(status) })}
            </Button>
          ))}
          <SetFieldDialog
            ids={ids}
            members={members}
            onDone={() => {
              setSelection({});
            }}
          />
          <Button
            size="sm"
            variant="destructive"
            className="ml-auto"
            disabled={bulk.pending}
            onClick={() => {
              void bulk.run({ kind: "delete", ids });
            }}
          >
            <Trash2Icon />
            {t("Delete")}
          </Button>
        </div>
      ) : null}
      <DataGrid table={table} recordCount={rows.length}>
        <DataGridContainer>
          <DataGridScrollArea>
            <DataGridTable />
          </DataGridScrollArea>
        </DataGridContainer>
      </DataGrid>
    </div>
  );
}
// #endregion recipe:record-grid
