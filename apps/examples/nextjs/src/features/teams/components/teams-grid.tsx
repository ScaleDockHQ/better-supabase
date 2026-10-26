"use client";

import type { CellContext, ColumnDef } from "@tanstack/react-table";

import { useTable } from "@tanstack/react-table";
import { useExtracted } from "next-intl";
import { useState } from "react";
import * as v from "valibot";

import type { DataGridFeatures } from "@/components/reui/data-grid/data-grid";

import { Badge } from "@/components/reui/badge";
import {
  DataGrid,
  DataGridContainer,
  dataGridFeatures,
} from "@/components/reui/data-grid/data-grid";
import { DataGridScrollArea } from "@/components/reui/data-grid/data-grid-scroll-area";
import { DataGridTable } from "@/components/reui/data-grid/data-grid-table";
import { Button } from "@/components/ui/button";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyTitle,
} from "@/components/ui/empty";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Link } from "@/i18n/navigation";

/** A team row as the grid shows it. */
export interface TeamRow {
  readonly id: string;
  readonly name: string;
  readonly description: string | null;
  readonly status: "active" | "archived";
  readonly memberCount: number;
}

const StatusFilter = v.picklist(["active", "archived", "all"]);

type StatusFilter = v.InferOutput<typeof StatusFilter>;

type TeamCell = CellContext<DataGridFeatures, TeamRow>;

function NameCell({ row }: TeamCell) {
  return (
    <Link
      href={`/settings/teams/${row.original.id}`}
      className="font-medium hover:underline"
    >
      {row.original.name}
    </Link>
  );
}

function DescriptionCell({ row }: TeamCell) {
  return (
    <span className="truncate text-muted-foreground">
      {row.original.description ?? "–"}
    </span>
  );
}

function MembersCell({ row }: TeamCell) {
  return <span className="tabular-nums">{row.original.memberCount}</span>;
}

function StatusCell({ row }: TeamCell) {
  const t = useExtracted("teams");

  return row.original.status === "active" ? (
    <Badge variant="success-light">{t("Active")}</Badge>
  ) : (
    <Badge variant="secondary">{t("Archived")}</Badge>
  );
}

/** The organization's teams with a search and a status filter. */
export function TeamsGrid({ teams }: { teams: readonly TeamRow[] }) {
  const t = useExtracted("teams");
  const [search, setSearch] = useState("");
  const [status, setStatus] = useState<StatusFilter>("active");

  const statusItems = [
    { value: "active", label: t("Active") },
    { value: "archived", label: t("Archived") },
    { value: "all", label: t("All teams") },
  ];

  const columns: ColumnDef<DataGridFeatures, TeamRow>[] = [
    { accessorKey: "name", header: t("Name"), cell: NameCell, size: 200 },
    {
      accessorKey: "description",
      header: t("Description"),
      cell: DescriptionCell,
      size: 280,
    },
    {
      accessorKey: "memberCount",
      header: t("Members"),
      cell: MembersCell,
      size: 100,
    },
    { accessorKey: "status", header: t("Status"), cell: StatusCell, size: 110 },
  ];

  const needle = search.trim().toLowerCase();

  const data = teams.filter(
    (team) =>
      (status === "all" || team.status === status) &&
      (needle === "" || team.name.toLowerCase().includes(needle)),
  );

  const table = useTable({
    features: dataGridFeatures,
    columns,
    data,
    getRowId: (row) => row.id,
  });

  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-center gap-2">
        <Input
          type="search"
          className="w-56"
          value={search}
          placeholder={t("Search teams")}
          aria-label={t("Search teams")}
          onChange={(event) => {
            setSearch(event.target.value);
          }}
        />
        <Select
          value={status}
          items={statusItems}
          onValueChange={(value) => {
            setStatus(v.is(StatusFilter, value) ? value : "active");
          }}
        >
          <SelectTrigger size="sm" className="w-36" aria-label={t("Status")}>
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {statusItems.map((item) => (
              <SelectItem key={item.value} value={item.value}>
                {item.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>
      <div data-testid="teams">
        <DataGrid
          table={table}
          recordCount={data.length}
          tableLayout={{ dense: true }}
          emptyMessage={
            <Empty>
              <EmptyHeader>
                <EmptyTitle>{t("No teams match")}</EmptyTitle>
                <EmptyDescription>
                  {t("Try another name or status.")}
                </EmptyDescription>
              </EmptyHeader>
              <EmptyContent>
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => {
                    setSearch("");
                    setStatus("all");
                  }}
                >
                  {t("Show all teams")}
                </Button>
              </EmptyContent>
            </Empty>
          }
        >
          <DataGridContainer>
            <DataGridScrollArea>
              <DataGridTable />
            </DataGridScrollArea>
          </DataGridContainer>
        </DataGrid>
      </div>
    </div>
  );
}
