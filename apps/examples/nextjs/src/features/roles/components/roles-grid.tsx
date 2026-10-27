"use client";

import type { CellContext, ColumnDef } from "@tanstack/react-table";

import { useTable } from "@tanstack/react-table";
import { useExtracted } from "next-intl";

import type { DataGridFeatures } from "@/components/reui/data-grid/data-grid";

import { Badge } from "@/components/reui/badge";
import {
  DataGrid,
  DataGridContainer,
  dataGridFeatures,
} from "@/components/reui/data-grid/data-grid";
import { DataGridScrollArea } from "@/components/reui/data-grid/data-grid-scroll-area";
import { DataGridTable } from "@/components/reui/data-grid/data-grid-table";
import { Link } from "@/i18n/navigation";

import { RoleName } from "./role-name";

/** A catalog role as the grid shows it. */
export interface RoleRow {
  readonly id: string;
  readonly key: string;
  readonly members: number;
  readonly permissions: number;
  readonly overrides: number;
}

type RoleCell = CellContext<DataGridFeatures, RoleRow>;

function NameCell({ row }: RoleCell) {
  const { id, key } = row.original;

  return (
    <Link
      href={`/settings/roles/${id}`}
      prefetch
      className="font-medium hover:underline"
    >
      <RoleName roleKey={key} />
    </Link>
  );
}

function CountCell({ getValue }: RoleCell) {
  return <span className="tabular-nums">{String(getValue())}</span>;
}

function OverridesCell({ row }: RoleCell) {
  const t = useExtracted("roles");
  const { overrides } = row.original;

  return overrides === 0 ? (
    <span className="text-muted-foreground">{t("Catalog default")}</span>
  ) : (
    <Badge variant="info-light">
      {t("{count, plural, one {# override} other {# overrides}}", {
        count: overrides,
      })}
    </Badge>
  );
}

/** The organization's catalog roles with their members and keys. */
export function RolesGrid({ roles }: { roles: readonly RoleRow[] }) {
  const t = useExtracted("roles");

  const columns: ColumnDef<DataGridFeatures, RoleRow>[] = [
    { accessorKey: "key", header: t("Role"), cell: NameCell, size: 180 },
    {
      accessorKey: "members",
      header: t("Members"),
      cell: CountCell,
      size: 110,
    },
    {
      accessorKey: "permissions",
      header: t("Permissions"),
      cell: CountCell,
      size: 130,
    },
    {
      accessorKey: "overrides",
      header: t("In this organization"),
      cell: OverridesCell,
      size: 180,
    },
  ];

  const table = useTable({
    features: dataGridFeatures,
    columns,
    data: [...roles],
    getRowId: (row) => row.id,
  });

  return (
    <div data-testid="roles">
      <DataGrid
        table={table}
        recordCount={roles.length}
        tableLayout={{ dense: true }}
      >
        <DataGridContainer>
          <DataGridScrollArea>
            <DataGridTable />
          </DataGridScrollArea>
        </DataGridContainer>
      </DataGrid>
    </div>
  );
}
