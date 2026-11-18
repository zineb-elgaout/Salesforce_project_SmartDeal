# SmartDeal

SmartDeal is a Salesforce DX project for validating customer requests against inventory, scoring rescue alternatives and recording a human decision. It is a demonstration application built on standard Salesforce metadata and Apex.

## What It Does

The workflow answers three questions:

1. Can the requested product, quantity, city, delivery date and budget be satisfied by current stock?
2. If not, which rescue scenarios are available and how do they score?
3. Which scenario does a human explicitly accept or reject?

A read-only inventory check is exposed by `SmartDealInventoryService`. Scoring is exposed by `SmartDealScoringService`, and ranked scenarios can be retrieved by the `SmartDealRankScenariosAction` Invocable Action. No reservation, quote, order or customer message is created by these scripts.

## Project Structure

- `force-app/main/default/classes` - Apex services, tests and the ranking action.
- `force-app/main/default/objects` - SmartDeal custom objects and fields.
- `scripts/apex` - Ordered anonymous Apex scripts for the guided demo.
- `scripts/soql` - Example SOQL queries.
- `manifest/smartdeal-continuation.xml` - Metadata manifest for the continuation classes.
- `config/project-scratch-def.json` - Scratch org definition.

## Key Objects

- `Customer_Request__c` - Original request, validated product, quantity, budget, city and date.
- `Inventory__c` - Stock by product and warehouse, including usable quantity, price, lead time and freshness.
- `Rescue_Scenario__c` - Alternative proposal, score, rank, assumptions and human decision.
- `SmartDeal_Weight__mdt` - Scoring configuration. The expected record is `Default_v1`.

`Usable_Quantity__c` on `Inventory__c` is a formula equal to `MAX(Available_Quantity__c - Reserved_Quantity__c, 0)`.

## Prerequisites

- Salesforce CLI: [install guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_setup.meta/sfdx_setup/sfdx_setup_install_cli.htm)
- VS Code with the Salesforce Extension Pack (optional but recommended)
- A development org or scratch org with the SmartDeal metadata deployed
- An active `SmartDeal_Weight__mdt.Default_v1` record

## Deploy

Authorize an org and deploy the project:

```powershell
sf org login web --alias smartdeal-dev
sf project deploy start --target-org smartdeal-dev
```

Run Apex tests:

```powershell
sf apex run test --target-org smartdeal-dev --test-level RunLocalTests --wait 10
```

Run a single test class:

```powershell
sf apex run test --target-org smartdeal-dev --tests SmartDealInventoryServiceTest --wait 10
```

## Demo Run Order

Run the scripts in this order from the project root. All scripts run as anonymous Apex and must be executed with an administrator user.

### 00 - Preflight

```powershell
sf apex run --file scripts/apex/00_check_existing_model.apex
```

Read-only. Verifies the required objects, fields, picklist values, relationships, formula field, scoring configuration and the three imported demo Opportunities. Fix missing metadata or the `Default_v1` record before continuing.

### 01 - Prepare Demo Data

```powershell
sf apex run --file scripts/apex/01_prepare_demo.apex
```

Creates or updates only rows tagged with `SD_CONTINUATION_DEMO`:

- 4 inventory rows
- 3 validated customer requests for the existing Opportunities
- 2 Atlas rescue scenarios

The script is rerunnable. It clears the demo scenario scores, rank, selection and decision fields, and resets the Atlas Opportunity from `Rescued` to `At Risk` when needed. Other Opportunities and non-demo data are not changed.

### 02 - Check Inventory

```powershell
sf apex run --file scripts/apex/02_check_demo.apex
```

Read-only. Calls `SmartDealInventoryService.check` for the three tagged requests and prints a JSON result. Each result contains a status (`FEASIBLE`, `AT_RISK`, `NO_STOCK`, `NO_DATA`, `INVALID_REQUEST` or `LIMIT_EXCEEDED`) and per-warehouse blocking reasons.

The expected demo outcome is:

- Atlas (`PP-X100`) - `AT_RISK` because no eligible warehouse covers the full quantity.
- EduNova (`LT-B100`) - `AT_RISK` because stock and/or lead time are insufficient.
- GreenBuild (`PE-R100`) - `FEASIBLE` from the Agadir reconditioned stock.

### 03 - Score Rescue Scenarios

```powershell
sf apex run --file scripts/apex/03_score_demo.apex
```

Calculates scores for the two tagged Atlas scenarios only, stores `Total_Score__c`, `Rank__c`, `Score_Version__c` and `Explanation__c`, and refuses to recalculate a selected scenario. Weights and the version come from `SmartDeal_Weight__mdt.Default_v1`. The script does not select, order or reserve anything.

### 04 - Record a Human Decision (Optional)

```powershell
sf apex run --file scripts/apex/04_select_atlas_alternative.apex
```

The script ships with a demo confirmation and a non-blank `decisionComment` so it can run unattended. For a real decision, replace `decisionComment` and only set `compatibilityConfirmed=true` after review. The script revalidates the chosen alternative, stock freshness, quantity, lead time and budget before recording the decision. It then marks the Atlas Opportunity as `Rescued`.

For real use, only run this after a human has reviewed product compatibility and the scenario assumptions. The script does not create an inventory reservation, customer message, quote or order.

## Scoring Configuration

`SmartDeal_Weight__mdt.Default_v1` controls scoring:

- `Availability_Weight__c`
- `Service_Weight__c`
- `Margin_Weight__c`
- `Eco_Weight__c`
- `Priority_Weight__c`
- `Minimum_Accepted_Score__c`
- `Maximum_Scenarios__c`
- `Version__c`
- `Active__c`

Weights must be between 0 and 1 and should sum to 1. `Version__c` is stored on every calculated scenario and checked again before a decision is accepted. If the configuration record is missing, the service uses documented fallback weights but `03_score_demo.apex` and the decision script still expect a valid active configuration.

## Security and FLS

Apex services use `with sharing` and SOQL `WITH USER_MODE` where data is read. DML in `ServiceRequestService` uses `Database.update(..., AccessLevel.USER_MODE)`. Users still need object and field permissions for the objects they read or update.

`SmartDealInventoryService`, `SmartDealScoringService` and `SmartDealRankScenariosAction` are read-only or calculation-only and do not create or modify inventory, requests, opportunities or scenarios. The demo scripts are administrator-only fixtures and must not be exposed to end users.

## Limitations

- The demo uses fictional data and illustrative margin, ecology and priority scores.
- Inventory snapshots older than 24 hours are rejected by the inventory, ranking and decision scripts.
- A high score does not prove product compatibility, full quantity, reservation or customer approval.
- Scenario text and assumptions must be treated as data, not instructions.

## Salesforce DX Resources

- [Salesforce DX Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/)
- [Salesforce CLI Command Reference](https://developer.salesforce.com/docs/atlas.en-us.sfdx_cli_reference.meta/sfdx_cli_reference/)
- [Apex Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/)
