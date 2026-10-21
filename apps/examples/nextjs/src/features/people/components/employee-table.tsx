"use client";

import type { EmployeeStatus } from "better-supabase/blocks/employees";
import type { ActionHandle } from "better-supabase/react";

import { useAction } from "better-supabase/react";
import { SearchIcon, SearchXIcon, TriangleAlertIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useDeferredValue, useState } from "react";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Input } from "@/components/ui/input";
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { useErrorMessage } from "@/lib/use-error-message";
import { cn } from "@/lib/utils";

import type { DirectoryEmployee } from "../people-queries";

import { getPrivateDetails } from "../people-actions";

/** Indents a name by its depth in the org chart, up to 4 levels. */
const INDENT = ["", "ps-6", "ps-12", "ps-18", "ps-24"] as const;

interface Details {
  readonly phone: string | null;
  readonly personalEmail: string | null;
  readonly birthDate: string | null;
}

function StatusBadge({ status }: { status: EmployeeStatus }) {
  const t = useExtracted("people");

  switch (status) {
    case "active": {
      return <Badge variant="success-light">{t("Active")}</Badge>;
    }

    case "preboarding": {
      return <Badge variant="info-light">{t("Preboarding")}</Badge>;
    }

    case "on_leave": {
      return <Badge variant="warning-light">{t("On leave")}</Badge>;
    }

    case "offboarded": {
      return <Badge variant="secondary">{t("Offboarded")}</Badge>;
    }

    default: {
      const unhandled: never = status;

      return unhandled;
    }
  }
}

function PrivateDetails({
  employeeId,
  read,
}: {
  employeeId: string;
  read: ActionHandle<{ employeeId: string }, Details | null>;
}) {
  const t = useExtracted("people");
  const errorMessage = useErrorMessage();

  if (read.pending || (read.data === undefined && read.error === undefined)) {
    return <Skeleton className="h-24" aria-busy="true" />;
  }

  if (read.error) {
    return (
      <Alert variant="destructive">
        <TriangleAlertIcon />
        <AlertTitle>{t("The private details didn't load")}</AlertTitle>
        <AlertDescription>{errorMessage(read.error)}</AlertDescription>
        <AlertAction>
          <Button
            size="sm"
            variant="outline"
            onClick={() => void read.run({ employeeId })}
          >
            {t("Retry")}
          </Button>
        </AlertAction>
      </Alert>
    );
  }

  const details = read.data;

  const rows = [
    { label: t("Phone"), value: details?.phone },
    { label: t("Personal email"), value: details?.personalEmail },
    { label: t("Birth date"), value: details?.birthDate },
  ];

  return (
    <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-2 text-sm">
      {rows.map((row) => (
        <div key={row.label} className="contents">
          <dt className="text-muted-foreground">{row.label}</dt>
          <dd>{row.value ?? t("Not set")}</dd>
        </div>
      ))}
    </dl>
  );
}

/**
 * The directory rows, indented under their manager, filtered by name, title or
 * email as you type.
 */
export function EmployeeTable({
  employees,
  canViewSensitive,
}: {
  employees: readonly DirectoryEmployee[];
  canViewSensitive: boolean;
}) {
  const t = useExtracted("people");
  const [query, setQuery] = useState("");
  const deferred = useDeferredValue(query.trim().toLowerCase());
  const [selected, setSelected] = useState<DirectoryEmployee | null>(null);
  const read = useAction(getPrivateDetails);

  const openDetails = (employee: DirectoryEmployee) => {
    setSelected(employee);
    read.reset();
    void read.run({ employeeId: employee.id });
  };

  const names = new Map(
    employees.map((employee) => [employee.id, employee.name]),
  );

  const shown =
    deferred === ""
      ? employees
      : employees.filter((employee) =>
          [employee.name, employee.jobTitle, employee.email].some((value) =>
            value?.toLowerCase().includes(deferred),
          ),
        );

  return (
    <div className="flex flex-col gap-4">
      <div className="relative max-w-sm">
        <SearchIcon className="pointer-events-none absolute top-1/2 left-2.5 size-4 -translate-y-1/2 text-muted-foreground" />
        <Input
          type="search"
          value={query}
          onChange={(event) => {
            setQuery(event.target.value);
          }}
          placeholder={t("Search by name, title or email")}
          aria-label={t("Search employees")}
          className="pl-8"
        />
      </div>
      {shown.length === 0 ? (
        <Empty className="border">
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <SearchXIcon />
            </EmptyMedia>
            <EmptyTitle>{t("No one matches")}</EmptyTitle>
            <EmptyDescription>
              {t("Try another name, title or email.")}
            </EmptyDescription>
          </EmptyHeader>
          <EmptyContent>
            <Button
              variant="outline"
              onClick={() => {
                setQuery("");
              }}
            >
              {t("Clear search")}
            </Button>
          </EmptyContent>
        </Empty>
      ) : (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{t("Name")}</TableHead>
              <TableHead>{t("Job title")}</TableHead>
              <TableHead>{t("Reports to")}</TableHead>
              <TableHead>{t("Status")}</TableHead>
              <TableHead className="text-right">{t("Reports")}</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {shown.map((employee) => (
              <TableRow key={employee.id}>
                <TableCell>
                  <div
                    className={cn(
                      "flex flex-col",
                      deferred === "" &&
                        INDENT[Math.min(employee.depth, INDENT.length - 1)],
                    )}
                  >
                    {canViewSensitive ? (
                      <button
                        type="button"
                        className="w-fit text-left text-sm font-medium underline-offset-4 transition-colors hover:underline"
                        onClick={() => {
                          openDetails(employee);
                        }}
                      >
                        {employee.name}
                      </button>
                    ) : (
                      <span className="text-sm font-medium">
                        {employee.name}
                      </span>
                    )}
                    {employee.email ? (
                      <span className="text-xs text-muted-foreground">
                        {employee.email}
                      </span>
                    ) : null}
                  </div>
                </TableCell>
                <TableCell>{employee.jobTitle ?? ""}</TableCell>
                <TableCell>
                  {employee.managerId
                    ? (names.get(employee.managerId) ?? "")
                    : ""}
                </TableCell>
                <TableCell>
                  <StatusBadge status={employee.status} />
                </TableCell>
                <TableCell className="text-right tabular-nums">
                  {employee.directReports}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}
      {canViewSensitive ? (
        <Sheet
          open={selected !== null}
          onOpenChange={(open) => {
            if (!open) {
              setSelected(null);
            }
          }}
        >
          <SheetContent>
            <SheetHeader>
              <SheetTitle>{selected?.name}</SheetTitle>
              <SheetDescription>
                {t("Only people who can see sensitive fields read these.")}
              </SheetDescription>
            </SheetHeader>
            <div className="px-4">
              {selected ? (
                <PrivateDetails employeeId={selected.id} read={read} />
              ) : null}
            </div>
          </SheetContent>
        </Sheet>
      ) : null}
    </div>
  );
}
