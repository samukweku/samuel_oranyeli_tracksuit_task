# Submission notes

## Running the project

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

The reusable mart consists of `dim_customer` and `fct_customer_subscription_month`. The fact has one row per subscription per calendar month that intersects its contract term. It retains customer attributes, contract dates/state, and recognised invoice revenue in NZD, supporting point-in-time subscription questions and customer-month revenue analysis beyond GRR.

Revenue is assigned to the calendar month of a `PAID` or `POSTED` invoice, using `total_nzd` as Tracksuit's functional currency. `VOIDED` invoices are excluded. A subscription is active in every calendar month from the month of `start_date` through the month of `end_date`, inclusive. This retains invoice revenue issued early in the same month as service start; revenue-recognition across invoice periods is not attempted because those periods are absent.

GRR first aggregates the subscription fact to customer-month. For every reporting month, it selects customers with positive revenue 12 months earlier, fixes that as cohort revenue, and caps each customer's current revenue at the baseline. Customer size is the current HubSpot attribute because no attribute history is supplied.

## Data quality observations

Thirteen billing accounts use a retired HubSpot ID present in `merged_object_ids`; `int_customer_id_map` resolves them to the surviving company. Two billing accounts have no CRM match. They are retained with a stable `unmatched:<account_id>` key and `Unknown` size group, rather than being dropped or fuzzily matched by name.

Invoice dates can fall outside exact subscription dates, commonly because billing occurs before service starts. The model uses month-level contract activity and invoice-month revenue, avoiding an incorrect day-level exclusion. Source records only provide current subscription and customer attributes, so no historical SCD accuracy is implied.
