// #region recipe:audit-log-table
import { useAuditLog } from "better-supabase/blocks/audit/react";
import { tenantOf, useAuth } from "better-supabase/react";
import { ActivityIndicator, Button, Pressable, Text, View } from "react-native";

import { API_SCHEMA } from "../lib/blocks";

/** A row of chips that filters by one value, or by none. */
function Chips({
  values,
  selected,
  onSelect,
}: {
  readonly values: readonly string[];
  readonly selected: string | undefined;
  readonly onSelect: (value: string | undefined) => void;
}) {
  return (
    <View style={{ flexDirection: "row", flexWrap: "wrap", gap: 6 }}>
      {[undefined, ...values].map((value) => (
        <Pressable
          key={value ?? "all"}
          accessibilityRole="radio"
          accessibilityState={{ checked: value === selected }}
          onPress={() => {
            onSelect(value);
          }}
          style={{
            borderWidth: 1,
            borderRadius: 16,
            paddingHorizontal: 10,
            paddingVertical: 2,
            backgroundColor: value === selected ? "#e5e5e5" : undefined,
          }}
        >
          <Text>{value ?? "All"}</Text>
        </Pressable>
      ))}
    </View>
  );
}

/**
 * The organization's audit trail, newest first, filtered by actor and by action
 * with the values on the loaded page. Members without `audit.read` get the
 * module's error.
 */
export function AuditLogTable() {
  const { entries, filters, hasMore, loading, error, setFilters, loadMore } =
    useAuditLog({ organizationId: tenantOf(useAuth()), schema: API_SCHEMA });

  const distinct = (values: readonly (string | undefined)[]) =>
    [...new Set(values.filter((value) => value !== undefined))].toSorted();

  const actors = distinct([
    ...(entries ?? []).map((entry) => entry.actorId),
    filters.actorId,
  ]);

  const actions = distinct([
    ...(entries ?? []).map((entry) => entry.eventType),
    filters.eventType,
  ]);

  return (
    <View style={{ gap: 8 }}>
      <Text style={{ fontSize: 17, fontWeight: "600" }}>Audit log</Text>
      <Chips
        values={actors}
        selected={filters.actorId}
        onSelect={(actorId) => void setFilters({ ...filters, actorId })}
      />
      <Chips
        values={actions}
        selected={filters.eventType}
        onSelect={(eventType) => void setFilters({ ...filters, eventType })}
      />
      {error ? <Text style={{ color: "#b91c1c" }}>{error.message}</Text> : null}
      {entries === undefined ? (
        <ActivityIndicator />
      ) : (
        entries.map((entry) => (
          <View key={entry.id} style={{ paddingVertical: 6 }}>
            <Text style={{ fontFamily: "monospace" }}>
              {entry.eventType ?? entry.op}
            </Text>
            <Text style={{ color: "#737373", fontSize: 12 }}>
              {entry.occurredAt.toLocaleString()} by{" "}
              {entry.actorLabel ?? entry.actorId ?? "the system"}
            </Text>
          </View>
        ))
      )}
      {hasMore ? (
        <Button
          title="Load more"
          disabled={loading}
          onPress={() => void loadMore()}
        />
      ) : null}
    </View>
  );
}
// #endregion recipe:audit-log-table
