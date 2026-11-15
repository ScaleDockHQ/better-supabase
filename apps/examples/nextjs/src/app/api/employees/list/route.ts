import { loadEmployeePage } from "@/features/people/people-queries";
import { employeeList } from "@/features/people/employees-list";
import { bsb } from "@/lib/supabase/server";

/**
 * `GET /api/employees/list?q=&status=&sort=&after=`: one page of employees,
 * searched, filtered and sorted by the employees block's page methods.
 */
export const GET = bsb.route(
  async (request, { db, tenant }) => {
    const query = employeeList.parse(request.nextUrl.searchParams);

    return Response.json(await loadEmployeePage(db, tenant, query.value));
  },
  { requireTenant: true, permission: "employees.read" },
);
