"use client";

import type { DbError } from "better-supabase";

import { useAction } from "better-supabase/react";
import { BookmarkIcon, SearchIcon, Trash2Icon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useState, useTransition } from "react";
import { toast } from "sonner";

import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
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
import {
  Field,
  FieldError,
  FieldGroup,
  FieldLabel,
} from "@/components/ui/field";
import { Input } from "@/components/ui/input";
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
import { usePathname, useRouter } from "@/i18n/navigation";
import { useErrorMessage } from "@/lib/use-error-message";

import {
  stateBadgeVariant,
  usePriorityLabel,
  useStateLabel,
  useWorkErrorHint,
} from "../use-work-labels";
import {
  deleteWorkView,
  saveWorkView,
  setWorkItemAssignee,
  setWorkItemStage,
} from "../work-actions";
import {
  type MemberOption,
  type SavedViewOption,
  type StageColumn,
  type WorkGridQuery,
  type WorkItemRow,
  WORK_ITEM_SORTS,
  WORK_ITEM_STATES,
  type WorkItemSort,
  workGridSearch,
} from "../work-types";
import { BulkActionBar } from "./bulk-action-bar";

const ANY = "";
const UNASSIGNED = "";

function useSortLabel(): (sort: WorkItemSort) => string {
  const t = useExtracted("work");

  return (sort) => {
    switch (sort) {
      case "newest": {
        return t("Newest");
      }

      case "title": {
        return t("Title");
      }

      case "priority": {
        return t("Priority");
      }

      case "state": {
        return t("State");
      }

      default: {
        const unknown: never = sort;

        return unknown;
      }
    }
  };
}

/** Saves the current filters and sort under a name. */
function SaveViewDialog({ query }: { query: WorkGridQuery }) {
  const t = useExtracted("work");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);
  const [name, setName] = useState("");
  const save = useAction(saveWorkView);
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
            void save
              .run({ name, q: query.q, state: query.state, sort: query.sort })
              .then((result) => {
                if (result.ok) {
                  toast.success(t("View saved"));
                  setName("");
                  setOpen(false);
                }
              });
          }}
        >
          <DialogHeader>
            <DialogTitle>{t("Save view")}</DialogTitle>
            <DialogDescription>
              {t("Keeps the search, the state filter and the sort.")}
            </DialogDescription>
          </DialogHeader>
          <FieldGroup>
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
          </FieldGroup>
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

// #region recipe:work-item-grid
/**
 * Work items as a table. The search, state filter and sort live in the URL
 * and can be saved as named views. State and assignee edit in place, and
 * the checkboxes feed the bulk action bar.
 */
export function WorkItemGrid({
  rows,
  stages,
  members,
  views,
  query,
  canWrite,
  canBulk,
}: {
  rows: readonly WorkItemRow[];
  stages: readonly StageColumn[];
  members: readonly MemberOption[];
  views: readonly SavedViewOption[];
  query: WorkGridQuery;
  canWrite: boolean;
  canBulk: boolean;
}) {
  const t = useExtracted("work");
  const router = useRouter();
  const pathname = usePathname();
  const errorMessage = useErrorMessage();
  const workErrorHint = useWorkErrorHint();
  const stateLabel = useStateLabel();
  const priorityLabel = usePriorityLabel();
  const sortLabel = useSortLabel();
  const [navigating, startTransition] = useTransition();
  const [search, setSearch] = useState(query.q);
  const [selected, setSelected] = useState<ReadonlySet<string>>(new Set());

  const onEditError = (error: DbError) => {
    toast.error(workErrorHint(error.hint) ?? errorMessage(error));
  };

  const stage = useAction(setWorkItemStage, { onError: onEditError });
  const assign = useAction(setWorkItemAssignee, { onError: onEditError });

  const removeView = useAction(deleteWorkView, {
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  const go = (next: WorkGridQuery) => {
    startTransition(() => {
      router.replace(`${pathname}${workGridSearch(next)}`);
    });
  };

  const visibleIds = new Set(rows.map((row) => row.id));
  const selection = [...selected].filter((id) => visibleIds.has(id));
  const selectedRows = rows.filter((row) => selected.has(row.id));
  const allSelected = rows.length > 0 && selection.length === rows.length;

  const stateItems = [
    { value: ANY, label: t("Any state") },
    ...WORK_ITEM_STATES.map((state) => ({
      value: state,
      label: stateLabel(state),
    })),
  ];

  const sortItems = WORK_ITEM_SORTS.map((sort) => ({
    value: sort,
    label: sortLabel(sort),
  }));

  const stageItems = stages.map((each) => ({
    value: each.id,
    label: each.name,
  }));

  const memberItems = [
    { value: UNASSIGNED, label: t("Unassigned") },
    ...members.map((member) => ({
      value: member.userId,
      label: member.name,
    })),
  ];

  const viewItems = views.map((view) => ({
    value: view.id,
    label: view.name,
  }));

  const activeView = views.find(
    (view) => workGridSearch(view.query) === workGridSearch(query),
  );

  return (
    <div className="flex flex-col gap-4" data-recipe="work-item-grid">
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
            placeholder={t("Search titles")}
            aria-label={t("Search titles")}
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
        <Select
          value={query.state ?? ANY}
          items={stateItems}
          onValueChange={(value) => {
            const state = WORK_ITEM_STATES.find((each) => each === value);

            go({ ...query, state: state ?? null });
          }}
        >
          <SelectTrigger size="sm" className="w-36" aria-label={t("State")}>
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {stateItems.map((item) => (
              <SelectItem key={item.value} value={item.value}>
                {item.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <Select
          value={query.sort}
          items={sortItems}
          onValueChange={(value) => {
            const sort = WORK_ITEM_SORTS.find((each) => each === value);

            go({ ...query, sort: sort ?? "newest" });
          }}
        >
          <SelectTrigger size="sm" className="w-36" aria-label={t("Sort")}>
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {sortItems.map((item) => (
              <SelectItem key={item.value} value={item.value}>
                {item.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <div className="ml-auto flex items-center gap-2">
          {views.length === 0 ? null : (
            <Select
              value={activeView?.id ?? null}
              items={viewItems}
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
                {viewItems.map((item) => (
                  <SelectItem key={item.value} value={item.value}>
                    {item.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          )}
          {activeView ? (
            <Button
              size="icon-sm"
              variant="ghost"
              aria-label={t("Delete view {name}", { name: activeView.name })}
              disabled={removeView.pending}
              onClick={() => {
                void removeView.run({ id: activeView.id });
              }}
            >
              <Trash2Icon />
            </Button>
          ) : (
            <SaveViewDialog query={query} />
          )}
        </div>
      </div>
      {canBulk ? (
        <BulkActionBar
          selected={selectedRows}
          onSettled={(failedIds) => {
            setSelected(new Set(failedIds));
          }}
        />
      ) : null}
      <Table>
        <TableHeader>
          <TableRow>
            {canBulk ? (
              <TableHead className="w-8">
                <Checkbox
                  checked={allSelected}
                  indeterminate={selection.length > 0 && !allSelected}
                  aria-label={t("Select all")}
                  onCheckedChange={(checked) => {
                    setSelected(
                      checked ? new Set(rows.map((row) => row.id)) : new Set(),
                    );
                  }}
                />
              </TableHead>
            ) : null}
            <TableHead>{t("ID")}</TableHead>
            <TableHead>{t("Title")}</TableHead>
            <TableHead>{t("State")}</TableHead>
            <TableHead>{t("Priority")}</TableHead>
            <TableHead>{t("Assignee")}</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {rows.map((row) => {
            const pendingStage = stage.pendingInputs.find(
              (input) => input.id === row.id,
            );

            const pendingAssignee = assign.pendingInputs.find(
              (input) => input.id === row.id,
            );

            const assignee = pendingAssignee
              ? (pendingAssignee.userId ?? UNASSIGNED)
              : (row.assigneeIds[0] ?? UNASSIGNED);

            return (
              <TableRow
                key={row.id}
                data-state={selected.has(row.id) ? "selected" : undefined}
              >
                {canBulk ? (
                  <TableCell>
                    <Checkbox
                      checked={selected.has(row.id)}
                      aria-label={t("Select {identifier}", {
                        identifier: row.identifier,
                      })}
                      onCheckedChange={(checked) => {
                        setSelected((current) => {
                          const next = new Set(current);

                          if (checked) {
                            next.add(row.id);
                          } else {
                            next.delete(row.id);
                          }

                          return next;
                        });
                      }}
                    />
                  </TableCell>
                ) : null}
                <TableCell className="text-muted-foreground tabular-nums">
                  {row.identifier}
                </TableCell>
                <TableCell className="font-medium">{row.title}</TableCell>
                <TableCell>
                  {canWrite && stages.length > 0 ? (
                    <Select
                      value={pendingStage?.stageId ?? row.stageId}
                      items={stageItems}
                      disabled={pendingStage !== undefined}
                      onValueChange={(value) => {
                        if (value !== null && value !== row.stageId) {
                          void stage.run({ id: row.id, stageId: value });
                        }
                      }}
                    >
                      <SelectTrigger
                        size="sm"
                        className="w-40"
                        aria-label={t("State of {identifier}", {
                          identifier: row.identifier,
                        })}
                      >
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {stageItems.map((item) => (
                          <SelectItem key={item.value} value={item.value}>
                            {item.label}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  ) : (
                    <Badge variant={stateBadgeVariant(row.state)}>
                      {stateLabel(row.state)}
                    </Badge>
                  )}
                </TableCell>
                <TableCell className="text-muted-foreground">
                  {priorityLabel(row.priority)}
                </TableCell>
                <TableCell>
                  {canWrite ? (
                    <Select
                      value={assignee}
                      items={memberItems}
                      disabled={pendingAssignee !== undefined}
                      onValueChange={(value) => {
                        void assign.run({
                          id: row.id,
                          userId:
                            value === null || value === UNASSIGNED
                              ? null
                              : value,
                        });
                      }}
                    >
                      <SelectTrigger
                        size="sm"
                        className="w-44"
                        aria-label={t("Assignee of {identifier}", {
                          identifier: row.identifier,
                        })}
                      >
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {memberItems.map((item) => (
                          <SelectItem key={item.value} value={item.value}>
                            {item.label}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  ) : (
                    <span className="text-sm text-muted-foreground">
                      {members.find((member) => member.userId === assignee)
                        ?.name ?? t("Unassigned")}
                    </span>
                  )}
                </TableCell>
              </TableRow>
            );
          })}
        </TableBody>
      </Table>
    </div>
  );
}
// #endregion recipe:work-item-grid
