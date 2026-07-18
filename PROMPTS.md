# Meaningful AI prompts

## Model-grain decision

> Review this dbt take-home brief and recommend a reusable dimensional grain for subscription retention reporting. The raw data contains CRM companies, billing accounts, subscription contracts, and invoice records. Explain how the grain should support “as of any given month” analysis without making GRR a one-off model.

I used the recommendation to build a subscription-calendar-month fact with contract attributes and monthly recognised revenue, plus a customer dimension.

## Messy customer identity decision

> Given a CRM company table where `merged_object_ids` contains retired IDs and a billing account table that references CRM IDs, propose a safe identity-resolution approach. Include how to handle billing accounts with no matching CRM ID, and avoid fuzzy name matching.

I verified the mapping against the raw data. Retired IDs map to the surviving company; unmatched billing accounts are retained as `Unknown` rather than dropped.

## GRR validation prompt

> Check this GRR SQL logic against this definition: for month M, use customers with positive revenue at M-12; divide their retained M revenue by their M-12 revenue; cap each customer's M revenue at M-12; segment by customer size. Identify risks around subscription-level versus customer-level aggregation.

I aggregate the fact to customer-month before creating the cohort, then cap revenue at customer level. I also ran `dbt build` to verify the implementation.
