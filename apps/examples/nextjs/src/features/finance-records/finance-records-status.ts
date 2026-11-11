/** The badge variant of a status value of any finance entity. */
export const statusVariant = (
  value: string,
):
  | "success-light"
  | "info-light"
  | "warning-light"
  | "destructive-light"
  | "secondary"
  | "outline" => {
  switch (value) {
    case "paid":
    case "approved":
    case "reimbursed":
    case "filed":
    case "exported":
    case "posted":
    case "active":
    case "matched":
    case "closed": {
      return "success-light";
    }
    case "issued":
    case "submitted":
    case "open": {
      return "info-light";
    }
    case "partially_paid":
    case "locked":
    case "unmatched": {
      return "warning-light";
    }
    case "uncollectible":
    case "cancelled": {
      return "destructive-light";
    }
    case "void":
    case "ignored":
    case "archived": {
      return "outline";
    }
    default: {
      return "secondary";
    }
  }
};
