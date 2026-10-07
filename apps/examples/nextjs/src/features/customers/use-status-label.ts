import { useExtracted } from "next-intl";

/** The values `customers_status_check` allows; anything else shows as is. */
export function useStatusLabel(): (status: string) => string {
  const t = useExtracted("customers");
  return (status) => {
    switch (status) {
      case "lead":
        return t("Lead");
      case "active":
        return t("Active");
      case "archived":
        return t("Archived");
      default:
        return status;
    }
  };
}
