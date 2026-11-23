-- Is on-time service equal across the 14 council districts? (FY2026)
-- Raw on-time rates mislead because districts file different mixes of request types (some types are
-- slower everywhere). "Expected" applies each type's citywide on-time rate to the district's own mix
-- (indirect standardization); gap = observed - expected, in percentage points.
WITH base AS (
    SELECT council_district, request_type_name, department_short, closed_on_time::int AS on_time
    FROM analytics.service_requests
    WHERE fiscal_year = 2026 AND sla_eligible AND council_district IS NOT NULL
),
type_rates AS (
    SELECT request_type_name, department_short, avg(on_time) AS citywide_rate
    FROM base
    GROUP BY request_type_name, department_short
),
district AS (
    SELECT
        b.council_district,
        count(*)               AS sla_eligible,
        avg(b.on_time)         AS observed_rate,
        avg(tr.citywide_rate)  AS expected_rate      -- = sum over types (n_dt * p_t) / n_d
    FROM base b
    JOIN type_rates tr USING (request_type_name, department_short)
    GROUP BY b.council_district
),
volume AS (
    SELECT
        council_district,
        count(*) AS requests,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY days_to_close) FILTER (WHERE is_resolved) AS median_days
    FROM analytics.service_requests
    WHERE fiscal_year = 2026 AND council_district IS NOT NULL
    GROUP BY council_district
)
SELECT
    d.council_district,
    v.requests                                                                  AS requests_fy2026,
    d.sla_eligible,
    round(100 * d.observed_rate, 1)                                             AS pct_on_time_observed,
    round(100 * d.expected_rate, 1)                                             AS pct_on_time_expected_for_mix,
    round(100 * (d.observed_rate - d.expected_rate), 1)                         AS gap_pts,
    -- normal-approximation 95% margin of error on the observed rate
    round(100 * 1.96 * sqrt(d.observed_rate * (1 - d.observed_rate) / d.sla_eligible), 1) AS moe_95_pts,
    round(v.median_days::numeric, 2)                                            AS median_days_to_close
FROM district d
JOIN volume v USING (council_district)
ORDER BY d.council_district;
