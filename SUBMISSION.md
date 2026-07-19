# Submission notes

## Running the project

The quickest path is:

```bash
make build
```

This creates the local virtual environment, installs dependencies, loads the CSVs, installs dbt packages, and runs all models and tests. The equivalent explicit commands are:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python3 load_raw_data.py
dbt deps
dbt build
```

`rpt_monthly_grr_by_customer_size` is the final reporting model. It is anchored to the latest month with recognised revenue in the supplied extract, so “last 12 months” is reproducible rather than dependent on the run date.

## Model design and assumptions

The reusable mart consists of `dim_customer`, `dim_subscription`, `dim_date`, and `fct_subscription_invoice`. The fact is atomic: it has one row per issued invoice, including voided invoices, so financial events are never pre-aggregated or discarded. `dim_subscription` provides the contract dates and state needed to identify subscriptions active as of any date; `dim_date` provides standard calendar attributes. Together, these support point-in-time subscription questions and financial analysis beyond GRR.

Revenue is assigned to the calendar month of a `PAID` or `POSTED` invoice, using `total_nzd` as Tracksuit's functional currency. `VOIDED` invoices are excluded. A subscription is active in every calendar month from the month of `start_date` through the month of `end_date`, inclusive. This retains invoice revenue issued early in the same month as service start; revenue-recognition across invoice periods is not attempted because those periods are absent.

GRR aggregates recognised invoice events to customer-month in the reporting layer. For every reporting month, it selects customers with positive revenue 12 months earlier, fixes that as cohort revenue, and caps each customer's current revenue at the baseline. Customer size is the current HubSpot attribute because no attribute history is supplied.

## Data quality observations

HubSpot's `company_id` identifies the current, canonical company record. Its `merged_object_ids` are retired IDs from older company records that were merged into it. Thirteen billing accounts reference one of those retired IDs; `int_customer_id_map` maps both current and retired IDs to the canonical `company_id` before customer joins. Two billing accounts have no CRM match. They are retained with a stable `unmatched:<account_id>` key and `Unknown` size group, rather than being dropped or fuzzily matched by name.

Invoice dates can fall outside exact subscription dates, commonly because billing occurs before service starts. The model uses month-level contract activity and invoice-month revenue, avoiding an incorrect day-level exclusion. Source records only provide current subscription and customer attributes, so no historical SCD accuracy is implied.
