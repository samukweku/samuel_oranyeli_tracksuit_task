# Meaningful AI prompts

I used AI as a design and review aid, not as an authority. For each prompt below, I inspected the raw data and validated the resulting implementation with dbt tests and `dbt build`.

## 1. Choose the dimensional grain

**Context:** The deliverable needs a reusable subscription model and a GRR proof point. The inputs are customer, account, subscription, and invoice extracts.

> Act as a senior data engineer. Given CRM companies, billing accounts, subscriptions, and invoice events, recommend a Kimball-style dimensional model that supports subscription “as of” questions and revenue retention reporting. Keep invoice events atomic; identify the dimensions required and state where month-level aggregation should occur.

**Decision taken:** I retained an atomic `fct_subscription_invoice`, with `dim_customer`, `dim_subscription`, and `dim_date`. Contract dates live in `dim_subscription`; the GRR model is the only layer that aggregates invoice events to customer-month.

**Verification:** Confirmed invoice ID uniqueness in the raw extract and added uniqueness/relationship tests to the fact. `dbt build` validates the complete dependency graph.

## 2. Resolve CRM identity safely

**Context:** Billing accounts refer to HubSpot IDs, some of which have been merged; two IDs do not exist in the CRM extract.

> Design a deterministic identity-resolution rule for a billing account's CRM ID when the CRM table includes a semicolon-separated list of merged IDs. Distinguish the current canonical `company_id` from retired IDs in `merged_object_ids`. Do not use fuzzy name matching. Explain how unmatched accounts should be represented so invoice revenue is not silently lost.

**Decision taken:** `int_customer_id_map` maps each current canonical HubSpot `company_id` to itself and every retired ID in `merged_object_ids` to that canonical company. Accounts without a map receive a stable `unmatched:<account_id>` customer key and `Unknown` segment.

**Verification:** Profiled the mapping before modelling: 13 accounts resolve through merged IDs and two remain unmatched. Relationship tests confirm every subscription and invoice has a valid dimensional parent.

## 3. Apply the GRR definition correctly

**Context:** GRR must use the fixed paying cohort from M-12 and exclude expansion.

> Review a proposed monthly GRR calculation. It must: aggregate invoice events to customer-month; select only customers with positive revenue at M-12; compare each customer to its own baseline; cap current revenue at baseline revenue; and segment the result by customer size. Identify common double-counting or cohort mistakes.

**Decision taken:** The reporting model aggregates recognised (`PAID`/`POSTED`) invoice revenue to customer-month before cohorting. It left joins the current month so churn becomes zero and uses `least(current_revenue, cohort_revenue)` before summing.

**Verification:** Added `dbt_utils` uniqueness and 0–100% bounds tests for the report. The output contains 12 reporting months (June 2025–May 2026) and all tests pass.
