# Tracksuit Take-Home Interview Preparation

This is a speaking guide, not a script to memorise. Lead with the business need, state the grain and assumptions precisely, then explain the engineering choice and its trade-offs. When challenged, distinguish what the submitted data supports from what a production system would require.

## 1. Your two-minute opening

> The business problem is to replace a semi-manual GRR process with a trusted, reusable subscription data foundation. GRR affects board reporting, Finance, Customer Success prioritisation, GTM planning, and Product investment, so I optimised for traceability and reuse rather than a single clever query.
>
> I separated the project into source declarations, typed staging views, identity-resolution intermediates, reusable dimensional marts, and a thin reporting mart. The core grain is one row per issued invoice in `fct_subscription_invoice`. `dim_customer` provides canonical CRM identity and segmentation, `dim_subscription` provides contract state and dates, and `dim_date` provides calendar semantics. The GRR report first aggregates invoice events to customer-month, fixes the cohort at M-12, left joins month M so churn becomes zero, and caps retained revenue customer by customer before aggregation so expansion cannot inflate GRR.
>
> I made three explicit calls: use paid and posted invoice-month NZD as the available revenue proxy; deterministically resolve merged HubSpot IDs without fuzzy matching; and retain unmatched billing customers under stable synthetic keys instead of dropping revenue. The build currently passes 58 of 58 models and tests. The main production gaps are service-period revenue recognition, historical customer segmentation, stronger anomaly/freshness controls, and incremental warehouse deployment.

## 2. Verified facts to know cold

- Raw input: 120 HubSpot companies, 122 billing accounts, 330 subscriptions, and 3,594 invoices.
- Identity: 120 matched billing accounts and 2 unmatched accounts. The crosswalk contains 19 retired IDs; 11 current billing accounts actually reference a retired ID.
- Subscription states: 111 active, 11 cancelled, and 208 expired rows.
- Invoice states: 3,321 paid, 160 posted, and 113 voided.
- Recognised revenue in this model is paid plus posted: NZD 7,904,203.40. Voided invoice value retained in the atomic fact but excluded from GRR is NZD 266,415.89.
- Date dimension: 3 June 2023 through 18 May 2027, 1,446 days.
- GRR output: June 2025 through May 2026, 60 rows, five segments per month, range 55.33% to 100%.
- Mean of monthly segment GRRs (not an overall weighted GRR): Enterprise 76.58%, Mid-Market 90.97%, SMB 94.68%, Startup 92.49%, Unknown 99.89%.
- 316 invoices fall outside their subscription's exact start/end dates. This supports the decision not to discard invoices using day-level contract filtering, but it also exposes the need for service-period fields in production.
- Current `dbt build`: 11 models, 47 data tests, 4 sources; 58/58 passed.
- Important correction: `SUBMISSION.md` says 13 accounts resolve through merged IDs. The current data/build produces 11. Say that the prose statistic became stale, own it, show the query, and explain that production documentation metrics should be generated or asserted rather than hand-maintained.

## 3. Architecture and dimensional modelling questions

### Q1. Walk us through the architecture.

**Answer:** Raw CSVs are loaded unchanged as strings into a `raw` DuckDB schema. dbt sources test primary identifiers and core relationships. Staging views rename, trim, standardise case, and cast types without introducing business joins. Two intermediate views resolve customer identity and map billing accounts to canonical customers. Core marts materialise customer, subscription, and date dimensions plus the atomic invoice fact. The reporting mart performs only the GRR-specific monthly aggregation and cohort logic. This makes source cleanup, identity policy, reusable business entities, and metric logic independently testable.

**Business lens:** Analysts and operational teams can reuse the core marts without copying GRR logic or reverse-engineering source quirks. Finance can trace a reported number back to invoice events.

### Q2. Why is the fact grain one row per invoice?

**Answer:** Invoice ID is unique and represents the lowest supplied financial event grain. Preserving it avoids premature monthly aggregation, retains voided events for audit, and supports questions beyond GRR: invoicing trends, currency analysis, billing status, customer revenue, and subscription performance. Monthly customer revenue belongs downstream because it is metric-specific.

### Q3. Is this really a subscription-over-time dimensional model?

**Answer:** It supports contract-as-of analysis through subscription start/end dates and revenue over time through dated invoice events. It is not a periodic subscription snapshot. That was a deliberate scope choice because the supplied subscriptions are current records with effective contract dates, not a change log. In production, if frequent point-in-time operational queries or historical status changes mattered, I would add a monthly subscription snapshot or an accumulating snapshot based on source history.

### Q4. Why is `dim_subscription` a dimension rather than a fact?

**Answer:** Each row describes a subscription contract: identifiers, state, effective dates, renewal lineage, and customer ownership. There are no additive measures at that grain. Invoice transactions reference it. If we introduced contract value, seats, quantity, or recurring charge schedules, a subscription fact or snapshot could sit alongside it.

### Q5. Why separate customer and subscription?

**Answer:** A customer can own multiple billing accounts and successive subscriptions. Combining them would duplicate customer attributes, blur grain, and make identity resolution harder. Separate dimensions preserve one canonical customer identity and one row per subscription while the fact carries their relationship.

### Q6. Why include `dim_date`?

**Answer:** It standardises reporting periods, supports consistent calendar attributes, and gives a conformed join target for invoice dates. It also creates reporting months even when no invoice occurs. In production I would use an organisation-wide date dimension with fiscal periods, holidays, local time conventions, and a stable configured range.

### Q7. Why views for staging/intermediate and tables for marts?

**Answer:** Views keep lightweight transformations transparent and avoid storing multiple copies of a small extract. Tables make reusable and reporting marts stable and performant for consumers. In a cloud warehouse I would base the choice on volume, concurrency, cost, SLAs, and query plans; large intermediates might become incremental tables or ephemeral CTEs.

### Q8. Why not put everything in one SQL model?

**Answer:** A single query would couple parsing, identity resolution, dimensional semantics, and GRR rules. That is harder to test, review, reuse, and change. The layered graph localises decisions: if HubSpot merge behaviour changes, the identity intermediate changes without rewriting every metric.

### Q9. Why use natural string keys rather than integer surrogate keys?

**Answer:** For this small single-source exercise, canonical source IDs are stable, readable, and simplify lineage. The synthetic `unmatched:<account_id>` key prevents null foreign keys. In production I would consider warehouse-generated surrogate keys, particularly for SCD2 dimensions, multiple source systems, key reuse, and privacy. The important property is a stable, collision-safe key and controlled crosswalk.

### Q10. What does “as of any month” mean here?

**Answer:** Contract activity can be inferred by comparing a month to subscription start and end dates; financial activity comes from invoice months. The submission does not claim historical accuracy for attributes such as customer segment or source-record state because only current values are supplied. I would state those two timelines separately to prevent consumers assuming more history than exists.

### Q11. How do renewal chains work?

**Answer:** `renewed_from_subscription_id` is retained in the subscription dimension, so consumers can follow predecessor relationships. GRR operates at canonical customer-month, so renewal to a new subscription ID does not falsely create churn as long as the billing account maps to the same customer. I would add tests for orphan predecessor IDs, self-links, cycles, and overlapping contract periods in production.

### Q12. Why use inner joins in the fact?

**Answer:** Source relationship tests prove every invoice subscription exists and every subscription account exists in this extract, so inner joins enforce valid dimensional references. In production I would usually create explicit “unknown” dimension members and alert on late-arriving facts rather than silently dropping them. The current tests fail the build before missing parents can be accepted unnoticed.

### Q13. What are the most important limitations of the model?

**Answer:** Invoice month is only a proxy for earned recurring revenue; customer attributes are current-state rather than historical; subscription statuses are not historically versioned; currency conversion methodology is supplied but not auditable; adjustments, credits, tax, proration, and service periods are absent; and the report is batch/full-refresh rather than incremental.

## 4. GRR definition and SQL questions

### Q14. Explain GRR in plain business language.

**Answer:** Take the customers paying a year ago and ask how much of that same revenue remains today, ignoring new customers and giving no credit for expansion. A 90% GRR means 10% of the starting revenue base was lost to churn or contraction over the year.

### Q15. Explain the calculation step by step.

**Answer:** First sum recognised NZD invoices to one row per customer and invoice month. Choose the latest revenue month and its preceding 11 months as report months. For each report month M, select customers with positive revenue at M-12 and record each customer's baseline. Left join that customer to M, replacing no revenue with zero. Cap current revenue with `least(current, baseline)` for each customer. Then sum capped retained revenue and divide by summed baseline revenue within the baseline customer-size segment.

### Q16. Why must the cap happen per customer before summing?

**Answer:** If the segment is aggregated first, one customer's expansion can offset another customer's churn, producing net revenue retention rather than gross retention. Per-customer `least()` ensures expansion contributes at most the customer's baseline.

### Q17. Why left join the current month?

**Answer:** The cohort is fixed at M-12. A cohort customer absent in M has churned for this calculation and must contribute zero. An inner join would remove churned customers from the numerator and bias GRR upward.

### Q18. Why require positive baseline revenue?

**Answer:** The business definition says customers paying at M-12. Positive revenue is the available operational definition of paying. It also avoids zero or negative denominators. In production Finance should explicitly define treatment of credits, zero-dollar contracts, refunds, and write-offs.

### Q19. Why are new customers excluded?

**Answer:** They are absent from the M-12 baseline join. GRR measures preservation of the existing book, not acquisition. New-logo performance belongs in growth, new ARR, or NRR analyses.

### Q20. How is expansion excluded?

**Answer:** `least(current_revenue_nzd, cohort_revenue_nzd)` is applied at customer level. If a customer grows from 100 to 150, retained revenue remains 100. If it contracts to 70, retained revenue is 70.

### Q21. What happens if a customer churns and later returns?

**Answer:** Under the stated M-12-versus-M definition, revenue present at M for the same canonical customer counts up to the baseline, even if there was an intervening gap. That is a logo identity interpretation. If the business wants reactivations excluded, we need a churn/reactivation policy and continuous-coverage logic.

### Q22. What happens when a customer changes segment?

**Answer:** The current implementation attaches the present HubSpot segment while building customer-month revenue, so historical rows are restated using the current segment. This is explicitly disclosed. For cohort analysis, I would normally segment by the customer's attribute as of M-12, using an SCD2 customer dimension or snapshot, so cohorts do not move retrospectively.

### Q23. Why anchor “last 12 months” to the data rather than today?

**Answer:** The extract is static. Anchoring to `max(invoice_month)` makes reviewer results reproducible and prevents an old fixture from returning empty future months. In production the semantic choice should be explicit: latest closed finance month, an orchestration-supplied reporting date, or current month if partial-month metrics are intended.

### Q24. Would you include the current partial month?

**Answer:** Usually not for board or Finance GRR. I would anchor to the latest closed accounting period and expose freshness/completeness status. Partial months systematically understate retained revenue.

### Q25. Why use invoice month instead of contract MRR/ARR?

**Answer:** Invoice events and NZD totals are the only supplied monetary measures. Without service start/end periods or recurring charge schedules, spreading revenue would invent precision. I used invoice month as a documented proxy. For real GRR, I would prefer a Finance-approved recurring revenue schedule normalised to monthly earned revenue.

### Q26. Does `PAID` plus `POSTED` represent GAAP revenue?

**Answer:** Not necessarily. It represents the exercise's available recognised-revenue proxy. Posted can mean issued rather than paid, and neither status proves revenue has been earned. I would align with Finance on invoice, booking, cash, and recognised-revenue definitions and name the model accordingly.

### Q27. Why exclude voided invoices but retain them in the fact?

**Answer:** A void should not contribute to the metric, but retaining the event supports auditability, reconciliation, and status analysis. The boolean flag makes metric inclusion explicit rather than deleting financial evidence upstream.

### Q28. What about credits and negative invoices?

**Answer:** The current fact test requires non-negative NZD totals because the supplied data satisfies that assumption. A production billing model must support credit notes, refunds, reversals, and adjustments. I would model event type and sign deliberately, then agree whether credits reduce the baseline, current revenue, or a restated period.

### Q29. Why report `current_cohort_revenue_nzd` as well as retained revenue?

**Answer:** It provides diagnostic visibility into actual current revenue before the expansion cap. Comparing it with retained revenue explains where expansion was removed and helps reconcile GRR against NRR-style figures.

### Q30. Why show cohort customer count?

**Answer:** It gives context for volatility and lets stakeholders distinguish a segment based on a few accounts from one with a broad base. For decision use I would also expose churned/contracted customer counts and revenue concentration.

### Q31. Is averaging the 12 monthly percentages valid?

**Answer:** Only as a descriptive average of reported monthly rates, not as annual GRR. Percentages with different denominators should not be averaged for a combined result. Recompute retained divided by baseline at the desired aggregate grain.

## 5. Identity and data-quality questions

### Q32. How do you resolve HubSpot merges?

**Answer:** The crosswalk maps every current `company_id` to itself and explodes semicolon-delimited retired IDs from `merged_object_ids`, mapping each retired ID to the current canonical company. Billing account `crmid` joins to that crosswalk. This is deterministic, auditable, and tested unique on the source ID.

### Q33. Why not fuzzy-match company names?

**Answer:** Names are mutable, duplicated, inconsistently formatted, and legally ambiguous. A false positive can attribute revenue to the wrong customer and corrupt retention. I prefer unmatched-but-retained revenue plus a stewardship queue. Fuzzy matching could generate candidates for human review, never silently establish financial identity.

### Q34. Why retain unmatched accounts?

**Answer:** Dropping them would make revenue disappear and overstate data quality. Stable synthetic keys preserve referential integrity and surface `Unknown` segmentation. The business can reconcile the amount and fix CRM links without changing historical fact identity unexpectedly.

### Q35. What if one retired ID maps to two current companies?

**Answer:** The uniqueness test on `source_company_id` fails. That is correct because the mapping is ambiguous and could duplicate facts. The pipeline should quarantine or block the affected identities and route them to CRM/data stewardship.

### Q36. Why is the mismatch in `SUBMISSION.md` important?

**Answer:** It demonstrates that hand-written data statistics drift. The correct current result is 11 billing accounts resolved through retired IDs, not 13. I would acknowledge it directly, correct the document, and turn important profiling claims into dbt singular tests, generated documentation, or a monitored audit model. Hiding it would be worse than the stale number.

### Q37. What data-quality tests are present?

**Answer:** Source and model uniqueness/not-null tests protect identifiers; relationship tests protect account-subscription-invoice and dimensional joins; accepted-values tests constrain segment, subscription state, and invoice status; fact amounts are non-negative; GRR is bounded 0–100; and report month plus segment is unique.

### Q38. What tests would you add first?

**Answer:** Source freshness; invoice account consistent with subscription account; invoice currency consistent with account/currency conversion metadata; subscription start before end; cancellation date within expected bounds; renewal parent existence/no cycles; merged-ID collision detection; no unintended invoice loss across transformations; report has 12 complete months and expected segments; reconciliation of recognised source revenue to fact and report; and anomaly thresholds for unmatched revenue.

### Q39. Are accepted-value tests too brittle?

**Answer:** They intentionally fail on new operational states so definitions are reviewed rather than silently excluded. In production I might use severity `warn` for newly observed descriptive values but `error` for states feeding financial logic, coupled with an “unknown state” quarantine and alert.

### Q40. What do the 316 invoices outside exact subscription dates mean?

**Answer:** Many invoices can be issued before service begins or around renewal boundaries, so day-level filtering would incorrectly discard real billing events. It also proves invoice date is not service period. I retained them, modelled contract activity separately, and would request invoice line service-period fields before claiming earned revenue.

### Q41. How would you reconcile the model to Finance?

**Answer:** Build control totals by month, currency, status, account, and invoice ID from raw to staging to fact; quantify exclusions such as voids; compare NZD totals to the billing ledger/general ledger; investigate differences with named reason codes; get Finance sign-off on period and status semantics; and publish freshness plus reconciliation status with the metric.

### Q42. How would late-arriving data be handled?

**Answer:** Use source ingestion timestamps and incremental models with a lookback window or merge strategy. Reprocess affected accounting periods when invoices, status, FX, identity, or customer attributes change. Keep idempotent loads and record metric restatements so downstream users know when historical GRR changed.

### Q43. How would you handle deleted source records?

**Answer:** Fivetran-style deletion metadata should be preserved. Financial facts generally should not vanish; mark tombstones, reconcile to source/ledger policy, and use snapshots or audit tables. Dimensions may become inactive while historical references remain valid.

## 6. Business and stakeholder questions

### Q44. Who are the consumers and what do they need?

**Answer:** Finance needs reconciled, closed-period numbers and auditability; executives/board need stable definitions and explanations of movement; Customer Success needs account-level drivers and timely risk signals; GTM needs segment/cohort trends; Product needs retention sliced by product/use case; analysts need reusable documented grains; engineering needs observability, ownership, and cost control.

### Q45. How would you establish GRR as a source of truth?

**Answer:** Co-author the definition with Finance and Revenue leadership; document inclusion/exclusion rules and examples; assign an owner; reconcile against prior reporting; run both systems in parallel; explain variances; certify closed months; expose lineage and freshness; and deprecate old spreadsheets only after stakeholder acceptance.

### Q46. What questions would you ask before productionising?

**Answer:** What is the authoritative recurring-revenue measure? Calendar or fiscal periods? Latest closed month or live month? How are credits, refunds, pauses, reactivations, acquisitions, transfers, multi-entity customers, plan migrations, and FX handled? Segment at cohort time or current time? Who approves restatements? What latency and availability SLA is required? Which system owns customer identity?

### Q47. How would Customer Success use this?

**Answer:** The aggregate GRR should drill to customer-level baseline, current, contraction, churn, renewal date, segment, and owner. CS needs leading indicators, not only a 12-month lagging metric, so I would pair it with renewal pipeline, product usage, support sentiment, and payment risk while keeping metric definitions separate.

### Q48. What action could Product take?

**Answer:** Compare retention by customer segment, product/package, tenure, cohort, and usage pattern to identify where customers fail to realise value. Correlation is not causation, so use the model to generate hypotheses and evaluate interventions rather than claim product features caused retention changes.

### Q49. How would you communicate a drop in Enterprise GRR?

**Answer:** First verify freshness, reconciliation, cohort size, concentration, and restatements. Then decompose into churn versus contraction and identify the few accounts driving the change. Compare prior cohorts and renewal timing. Present what happened, financial magnitude, confidence/data caveats, likely drivers, owners, and next actions—not just the percentage.

### Q50. How do you avoid metric misuse?

**Answer:** Publish definitions next to the dashboard, distinguish GRR from NRR/logo retention, label partial periods, show denominator and cohort counts, restrict uncertified periods, provide drill-through, and educate users on segment history and invoice-month limitations.

### Q51. How would you prioritise future work?

**Answer:** Prioritise by decision risk and business value: first Finance-approved revenue semantics and reconciliation; second historical identity/segment correctness; third reliable incremental operation and observability; fourth self-service drill-down and semantic-layer metrics; then richer product/CS enrichment.

### Q52. What business risk does identity resolution create?

**Answer:** Incorrect merges can combine unrelated revenue or split one customer's history, distorting churn and concentration. Changes need stewardship, effective dating, audit logs, impact analysis, and controlled backfills—especially before board reporting.

## 7. Production engineering questions

### Q53. How would this change on Snowflake/BigQuery/Databricks?

**Answer:** Preserve the logical layers but replace DuckDB-specific functions where necessary, use managed schemas and environment targets, externalise credentials, add incremental strategies and clustering/partitioning, use CI state selection/defer, define grants and masking, and validate query cost and concurrency. Keep business logic adapter-portable where practical.

### Q54. How would you make models incremental?

**Answer:** Invoice facts merge on immutable invoice ID and reprocess records whose source update timestamp changed, plus a safety lookback. Identity and subscription changes can affect historical joins, so either use effective-dated dimensions with keys resolved at fact time or explicitly backfill impacted customers/periods. The GRR mart recalculates at least the last 24–25 months because each output month depends on M and M-12.

### Q55. What orchestration would you use?

**Answer:** Run ingestion first, validate source freshness/volume, execute dbt build by state or tags, reconcile controls, publish artifacts, and only then refresh downstream BI. Alerts should include owner, affected periods, business impact, and a runbook. Production deployment should be idempotent and environment-promoted.

### Q56. How would CI/CD work?

**Answer:** On pull requests: SQL/YAML linting, compile, unit/singular tests, modified-state dbt build in an isolated schema, documentation coverage, and code review. On merge: deploy immutable code, run in staging then production, retain artifacts, and support rollback. Protect metric-contract changes with domain-owner review.

### Q57. What observability matters?

**Answer:** Freshness, row counts, schema drift, null/duplicate rates, relationship failures, unmatched-customer count and revenue, revenue reconciliation, duration/cost, report completeness, unusual GRR movement, and lineage. Alerts should be severity-based to avoid noise.

### Q58. How would you secure this data?

**Answer:** Apply least-privilege service roles, environment-separated credentials, encrypted storage/transit, row/column policies for customer-sensitive fields, audited access, retention policies, and safe non-production fixtures. Expose only necessary attributes to broad BI consumers.

### Q59. How would you support schema evolution?

**Answer:** Detect source schema changes, contract critical staging columns, quarantine incompatible changes, version semantic contracts, and communicate downstream impact. Add new nullable fields compatibly; treat changed identifiers, status semantics, or financial fields as breaking changes.

### Q60. Why keep raw data as strings?

**Answer:** It preserves landed source fidelity and makes parsing policy explicit in staging. It is useful for this fixture loader, though production ingestion should also preserve source metadata, types where reliable, extraction timestamps, and rejected records.

### Q61. What dbt features could strengthen this?

**Answer:** Snapshots for mutable customer/subscription history, model contracts for stable marts, exposures for dashboards, source freshness, unit tests for GRR edge cases, tags/owners/meta, semantic-layer metrics, incremental models, and generated docs with lineage.

### Q62. How would you test the GRR SQL with fixtures?

**Answer:** Create small cases for full retention, total churn, contraction, expansion cap, new customer exclusion, multiple invoices, renewal to a new subscription, missing current row, segment change, voided invoice, zero baseline, credit note, and reactivation. Assert exact customer-level retained values and segment totals.

### Q63. What performance bottleneck appears at scale?

**Answer:** Repeatedly aggregating the full atomic invoice fact and joining M to M-12. I would maintain an incremental customer-month recurring-revenue fact, partition/cluster by month and customer, and calculate rolling cohort comparisons from that certified layer while retaining invoice drill-through.

## 8. Alternatives and challenge questions

### Q64. Why not build a monthly snapshot fact from the start?

**Answer:** A snapshot is attractive for as-of queries, but the only monetary events supplied are invoices and no reliable service-period allocation exists. Creating monthly recurring values would invent assumptions. I kept atomic evidence and deferred monthly aggregation to the report. With contract schedules, a periodic `fct_customer_recurring_revenue_monthly` would be my preferred production addition.

### Q65. Why not model account as its own dimension?

**Answer:** Account is currently a bridge between billing and customer identity, and the requested analyses do not need account attributes beyond mapping. A production model likely deserves `dim_billing_account`, especially for multiple accounts per customer, legal entities, billing currencies, ownership changes, and account-level reconciliation.

### Q66. Why not follow renewal chains for GRR?

**Answer:** Customer-level aggregation already makes renewal IDs irrelevant to retention if identity is stable. Traversing chains would add complexity and can fail on malformed lineage. Renewal chains remain useful for contract lifecycle and renewal analysis, not necessary for this GRR definition.

### Q67. Why is segment taken from baseline rows if the dimension is current?

**Answer:** The baseline revenue rows carry a segment label, but that label was joined from the current-state dimension, so it is not truly historical. The SQL structure is ready for as-of segmentation once an SCD2 dimension exists; the limitation is source history, not the cohort grouping mechanism.

### Q68. Could invoice fluctuations misclassify contraction?

**Answer:** Yes. Billing cadence, timing, proration, credits, annual invoicing, and currency changes can move invoice-month amounts without economic contraction. That is the biggest semantic caveat. A recurring-revenue schedule or normalised MRR is required for production-quality subscription GRR.

### Q69. Are paid and posted mutually safe to sum?

**Answer:** In this extract each invoice is one current row with one status, so there is no duplication across statuses. With status-history events, I would deduplicate to the latest state per invoice or model state transitions separately. I would also clarify whether posted-but-unpaid belongs in Finance's GRR.

### Q70. What would you change if given another day?

**Answer:** Correct the stale merged-account statistic; add GRR unit fixtures and revenue reconciliation tests; document every mart column and owner; add account consistency and date-range tests; expose a customer-level GRR diagnostic model; and add an architecture/lineage diagram. I would not silently invent service-period revenue.

### Q71. What decision are you least confident about?

**Answer:** Treating invoice-month paid/posted value as recognised recurring revenue. It is defensible for the supplied columns and clearly disclosed, but it needs Finance validation. Naming that uncertainty is good engineering because the wrong financial semantic can make perfectly tested SQL misleading.

### Q72. What are you most confident about?

**Answer:** The grain discipline, customer-level GRR cap, fixed M-12 cohort, deterministic identity resolution, retention of unmatched revenue, and layered separation. These choices are directly supported by the data and business definition.

## 9. AI-use questions

### Q73. How did you use AI?

**Answer:** I used it to pressure-test three meaningful decisions: dimensional grain, deterministic CRM identity resolution, and the GRR cohort/capping logic. `PROMPTS.md` records context, the decision taken, and how I verified it. I did not treat generated output as authority.

### Q74. How did you verify AI output?

**Answer:** I inspected the raw data, checked identifier uniqueness and mappings, reviewed compiled SQL logic, added structural and business-rule tests, and ran the full dbt build. I remain accountable for every line and can explain the limitations.

### Q75. What would you never delegate blindly?

**Answer:** Financial metric definitions, identity merges, destructive migrations, access/security changes, and final production approval. AI can generate options and tests, but accountable humans and domain owners must decide semantics and risk.

### Q76. What did AI miss or what did you catch?

**Answer:** The stale “13 merged-ID accounts” prose demonstrates why generated or manually copied profiling claims need revalidation. The present query says 11. My lesson is to encode key assertions in executable controls and rerun them before submission.

## 10. Behavioural questions with adaptable STAR answers

Do not invent experience. Replace brackets with a real example from your history and keep each answer to roughly two minutes.

### Q77. Tell us about yourself and why Tracksuit.

**Answer structure:** “I’m a data engineer focused on turning ambiguous operational data into trusted products. My strongest work sits between technical modelling and stakeholder decisions: [brief example]. Tracksuit appeals because it is scaling its data foundations and the work directly influences Finance, Customer Success, GTM, and Product. This exercise—identity ambiguity, metric definition, and reusable modelling—is the kind of problem I enjoy.”

### Q78. Tell us about ambiguity you handled.

**STAR:** Situation: [messy sources/unclear metric]. Task: deliver a useful answer without pretending certainty. Action: identified decision owners, profiled data, wrote assumptions, presented options/trade-offs, chose a reversible rule, added monitoring. Result: [decision/time/quality outcome]. Reflection: distinguish a documented assumption from a verified fact.

### Q79. Tell us about influencing a non-technical stakeholder.

**STAR:** Lead with their decision, not architecture. Quantify the impact of inconsistent definitions, show a small reconciliation or prototype, agree acceptance criteria, and communicate trade-offs in business terms. Result: [adoption or reduced manual work].

### Q80. Tell us about disagreement over a metric.

**STAR:** Bring concrete edge cases—expansion, credits, reactivation, segment movement—to reveal semantic differences. Facilitate a decision with Finance/business owners, record the definition and owner, backtest both options, and version changes. Avoid winning by technical authority.

### Q81. Tell us about a production incident.

**STAR:** Explain detection, customer/business impact, containment, communication cadence, root cause, recovery, and prevention. Own your part without blame. Mention a concrete control added afterward and evidence that recurrence risk fell.

### Q82. Tell us about balancing speed and quality.

**STAR:** Classify irreversible/high-risk decisions versus reversible ones. Ship a thin trusted slice with explicit constraints, tests, monitoring, and follow-up dates. Use the take-home as an example: atomic evidence and documented assumptions now; service-period modelling only with sufficient data.

### Q83. Tell us about technical debt you prioritised.

**STAR:** Quantify business drag, incident risk, or delivery delay; propose a bounded remediation; align it with a roadmap outcome; deliver incrementally; measure improvement. Do not frame all imperfect code as urgent debt.

### Q84. How do you collaborate across teams?

**Answer:** Start with shared outcomes and decision rights. Agree definitions and interfaces early, make work visible, write concise design records, invite review from affected teams, provide self-service documentation, and close the loop after launch. Tailor depth: Finance needs reconciliation, analysts need grain/lineage, platform engineers need SLAs/contracts.

### Q85. How do you receive feedback?

**Answer:** Ask for concrete examples and impact, separate intent from outcome, verify the issue, state what you will change, and follow up. For this submission, a challenge to invoice-month revenue or the stale profiling count should be met with acknowledgement and a better control, not defensiveness.

### Q86. How do you give feedback?

**Answer:** Timely, specific, and about observable work or impact. Confirm shared goals, ask about context, distinguish blocking risks from preferences, suggest a path forward, and recognise good decisions. Escalate privately and respectfully when needed.

### Q87. How do you mentor others?

**Answer:** Explain reasoning and trade-offs, not only the answer; pair on one real problem; provide safe ownership; review with questions; document reusable patterns; and gradually remove support. Measure success by independent judgment, not dependence on you.

### Q88. Describe a failure.

**STAR:** Choose a genuine error with meaningful ownership. State early signals you missed, impact, immediate correction, systemic prevention, and changed behaviour. A strong answer shows calibrated accountability rather than a disguised strength.

### Q89. How do you prioritise competing requests?

**Answer:** Clarify expected decisions, value, urgency, risk, effort, dependencies, and reversibility. Make capacity and trade-offs visible, agree priorities with accountable owners, and revisit when evidence changes. Protect reliability and regulatory/financial correctness from ad hoc urgency.

### Q90. What environment helps you do your best work?

**Answer:** Clear outcomes with autonomy on implementation, candid review, accessible stakeholders, strong ownership, room to improve systems, and teams that value both delivery and learning. Add a real example of how you create those conditions rather than only requesting them.

### Q91. How would you handle an urgent request for an uncertified GRR number?

**Answer:** Understand the decision and deadline; provide the latest certified figure if possible; clearly label any provisional output, caveats, and confidence; run targeted reconciliation; notify the metric owner; and commit to a certification time. Never silently present provisional data as board-ready.

### Q92. What would your first 90 days look like?

**Answer:** First 30: learn business definitions, stakeholders, architecture, incidents, and pain points; ship a small useful improvement. Days 31–60: own a bounded data product, improve tests/observability, and document contracts. Days 61–90: deliver a cross-functional outcome, propose a prioritised roadmap grounded in measured risk/value, and help strengthen team practices.

## 11. Rapid-fire questions

### Q93. GRR versus NRR?

**Answer:** GRR caps each customer's current revenue at baseline and excludes expansion; NRR includes expansion. Both exclude new customers from the starting cohort.

### Q94. Revenue retention versus logo retention?

**Answer:** Revenue retention weights customers by revenue; logo retention weights each customer equally. Both can be useful and tell different stories.

### Q95. Fact versus dimension?

**Answer:** Facts record measurable events at a declared grain; dimensions describe the entities and context used to slice those events.

### Q96. SCD1 versus SCD2 here?

**Answer:** Current customer dimension behaves like SCD1/current state. SCD2 would preserve effective-dated segment and other attribute history, enabling correct as-of cohort segmentation.

### Q97. Why `nullif(trim(x), '')`?

**Answer:** It standardises whitespace-only strings to null, making missingness consistent and testable.

### Q98. Why uppercase statuses and currency?

**Answer:** To eliminate casing variants before accepted-value checks and business filters.

### Q99. Why decimal rather than float for money?

**Answer:** Fixed precision avoids binary floating-point rounding surprises in financial calculations.

### Q100. Why `nullif(sum(baseline), 0)`?

**Answer:** It prevents divide-by-zero. Positive baseline filtering should already make the denominator positive, so it is a defensive guard.

### Q101. Why test GRR between 0 and 100?

**Answer:** The customer-level cap and non-negative assumptions imply that bound. A failure signals a logic or data-sign issue.

### Q102. What is one row in the final report?

**Answer:** One report month and one customer-size group, containing the fixed M-12 cohort's counts, baseline revenue, current revenue, capped retained revenue, and GRR percentage.

## 12. Questions to ask the Tracksuit team

Choose five to eight based on the conversation; do not machine-gun the entire list.

1. How is GRR defined and governed today, and which edge cases create the most debate?
2. What is the authoritative recurring-revenue source: billing invoices, contracts, a Finance schedule, or another model?
3. How do Finance, Customer Success, Product, and GTM consume retention data differently?
4. What data-quality or identity-resolution problems consume the most team time today?
5. Where is the current data platform strongest, and where is scale-up pressure showing first?
6. How are metric ownership and semantic changes decided and communicated?
7. What would success for this role look like after three and twelve months?
8. What balance does the role have between platform engineering, modelling, stakeholder work, and enablement?
9. How are dbt models deployed, tested, observed, and cost-managed today?
10. How does the team handle historical restatements in executive or board metrics?
11. What is the customer/account identity strategy across HubSpot, billing, product, and support systems?
12. Which upcoming company decisions most need better data foundations?
13. How does the data team partner with application engineers on event and source contracts?
14. How do you use AI in engineering work, and what review expectations have proven effective?
15. Can you share a recent example where the team changed its mind because of data?
16. What distinguishes engineers who thrive at Tracksuit from those who struggle?
17. How are technical debt and reliability work prioritised against new stakeholder requests?
18. What learning, pairing, and feedback practices does the team use?

## 13. Whiteboard-ready explanation

```text
HubSpot companies ──> staging ──> canonical/retired ID crosswalk ─┐
                                                                  ├─> dim_customer
Subskribe accounts ─> staging ──> account-to-customer mapping ────┤
                                                                  └─> dim_subscription
Subskribe subscriptions ──────────────────────────────────────────┘         │
                                                                             │
Subskribe invoices ─> staging ───────────────────────────────────────────────┼─> atomic invoice fact
Date spine ──────────────────────────────────────────────────────────────────┘

atomic invoice fact + customer dimension
  -> recognised NZD revenue per customer-month
  -> cohort customers with positive revenue at M-12
  -> left join their revenue at M (missing = zero)
  -> retained per customer = min(M revenue, M-12 revenue)
  -> aggregate by M and baseline segment
  -> GRR = retained / baseline
```

## 14. Final interview checklist

- Be able to state every grain without looking.
- Start every technical answer with the business consequence.
- Do not call invoice-month totals true accounting revenue without qualification.
- Explicitly acknowledge current-state segment history.
- Explain why the expansion cap is per customer.
- Explain why the current-month join is left, not inner.
- Own and correct the 13-versus-11 stale documentation count.
- Mention that all 58 build nodes/tests pass, but do not equate passing tests with correct business semantics.
- Use real behavioural examples; never invent details.
- Bring two or three questions tailored to each interviewer.
- Close by connecting your approach to Tracksuit's scale-up need: trusted definitions, reusable foundations, cross-functional adoption, and pragmatic delivery.
