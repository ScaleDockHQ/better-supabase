import "server-only";
import { recordListServer } from "better-supabase/next";
import { defineRecordList } from "better-supabase/records";

import { customerList } from "@/lib/lists";
import { customerFeature } from "@/lib/supabase/features/customer/customer-feature";
import { bsb } from "@/lib/supabase/server";

/**
 * The customer list with the comment count per row, filled for the whole page
 * in one request. The column is hidden without `comments.read`.
 */
const customerRecordList = defineRecordList(customerFeature, customerList, {
  columns: { comments: "count" },
});

export const customerRecords = recordListServer(bsb, customerRecordList);
