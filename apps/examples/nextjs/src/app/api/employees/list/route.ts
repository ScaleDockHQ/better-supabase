import { employeeList, employeeSpec } from "@/features/people/employees-list";
import { readDirectory } from "@/features/people/people-queries";
import { pageBlockRows } from "@/lib/block-list";
import { bsb } from "@/lib/supabase/server";

/**
 * `GET /api/employees/list?q=&status=&sort=&after=`: one page of employees,
 * searched, filtered and sorted on the server.
 */
export const GET = bsb.route(
  async (request, { db, tenant }) => {
    const rows = await readDirectory(db, tenant);
    const query = employeeList.parse(request.nextUrl.searchParams);

    return Response.json(
      pageBlockRows(employeeList, employeeSpec, rows, query.value),
    );
  },
  { requireTenant: true, permission: "employees.read" },
);
