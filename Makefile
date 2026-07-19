.DEFAULT_GOAL := help

VENV := .venv
PYTHON := $(VENV)/bin/python
DBT := $(VENV)/bin/dbt

.PHONY: help setup load deps build

help: ## Show available commands.
	@awk 'BEGIN {FS = ":.*##"}; /^[a-zA-Z_-]+:.*##/ {printf "%-8s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

$(PYTHON):
	python3 -m venv $(VENV)

setup: $(PYTHON) ## Create the virtual environment and install Python dependencies.
	$(PYTHON) -m pip install -r requirements.txt

load: setup ## Load the supplied CSVs into the local DuckDB database.
	$(PYTHON) load_raw_data.py

deps: setup ## Install dbt packages.
	$(DBT) deps --profiles-dir .

build: load deps ## Load data, install packages, and run all models and tests.
	$(DBT) build --profiles-dir .
