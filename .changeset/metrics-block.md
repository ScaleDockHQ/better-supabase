---
"better-supabase": minor
---

Adds the `metrics` block (`better-supabase/blocks/metrics`). `defineMetric` declares a count, sum or average over a table with dimensions, a time zone and a permission. Metrics roll up into `metric_points` per grain through a `metrics.rollup` job or `metricsSink`, or are read from the table directly. `series()` and `kpi()` compare with the previous range, and `toChartData` returns Recharts rows. Usage events can be a metric's source.
