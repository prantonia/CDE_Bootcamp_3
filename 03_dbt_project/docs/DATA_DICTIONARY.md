# Data dictionary

Generated from the dbt project (`scripts/generate_data_dictionary.py`). Do not edit by hand: change the
description in the model's `.yml` file and regenerate. Column types are those of the warehouse the docs
were generated against.

**Conventions.** NULL in `clicks` / `impressions` means *not reported* (unknown), not zero. `spend` is in the
account currency (`currency_code`); `spend_eur` is comparable across platforms. `country_code = 'UNSPECIFIED'`
means the platform gives no country breakdown (all Facebook rows). Ratio metrics (CTR, CPC, CPM) must be
recomputed from sums, never averaged.

## Marts (gold): the tables analysts, BI tools and AI agents should query

### `dim_marketing_ads`

Ad dimension. **Grain: one row per platform x ad (`ad_key`).** Descriptive attributes of every ad that has reported performance, plus the first/last date it reported and how many days it reported.

*Materialization:* `table`

| Column | Type | Description | Tests |
|---|---|---|---|
| `ad_key` | varchar | Primary key. Surrogate hash of platform + source_ad_id. | not_null, relationships, unique |
| `platform` | varchar | Advertising platform. | accepted_values, not_null |
| `source_ad_id` | varchar | The platform's own ad id. | not_null |
| `ad_name` | varchar | Ad / creative name. |  |
| `ad_status` | varchar | Delivery status. NULL for Snapchat. |  |
| `source_ad_group_id` | varchar | The platform's ad group id. |  |
| `ad_group_name` | varchar | Ad group name. |  |
| `campaign_key` | varchar | Surrogate key of platform + source_campaign_id. | not_null |
| `source_campaign_id` | varchar | The platform's own campaign id. |  |
| `campaign_name` | varchar | Campaign name. |  |
| `source_account_id` | varchar | The platform's ad account id. |  |
| `account_name` | varchar | Ad account name. NULL for Snapchat. |  |
| `currency_code` | varchar | Currency of the account the ad bills in. |  |
| `first_report_date` | date | First date the ad reported performance. |  |
| `last_report_date` | date | Last date the ad reported performance. |  |
| `reported_days` | bigint | Number of distinct dates the ad reported performance. |  |

### `fct_marketing_ad_performance_daily`

The unified marketing fact: Facebook and Snapchat advertising performance in one consistent shape. **Grain: one row per platform x ad x report date x country** (`performance_key`). Facebook has no country breakdown, so its rows carry country `UNSPECIFIED`. Descriptive names (campaign, ad group, ad, account) are denormalized onto the row so analysts and AI agents can answer most questions without joins. Ratio metrics (CTR, CPC, CPM) are deliberately NOT stored per row because they cannot be averaged; use `rpt_marketing_campaign_daily` / `rpt_marketing_platform_monthly`, or recompute from sums. Incremental: new days are appended and the trailing `incremental_lookback_days` days are re-merged to pick up platform restatements.

*Materialization:* `incremental`

| Column | Type | Description | Tests |
|---|---|---|---|
| `performance_key` | varchar | Primary key. Surrogate hash of platform + source_ad_id + report_date + country_code. | not_null, unique |
| `ad_key` | varchar | Surrogate key of platform + source_ad_id. Joins to `dim_marketing_ads`. | not_null, relationships |
| `campaign_key` | varchar | Surrogate key of platform + source_campaign_id. | not_null |
| `platform` | varchar | Advertising platform the row comes from. | accepted_values, not_null |
| `report_date` | date | Calendar date the performance relates to. | not_null |
| `country_code` | varchar | Upper-case ISO country code of the delivery breakdown; `UNSPECIFIED` where the platform gives none (all Facebook rows). | not_null |
| `source_ad_id` | varchar | The platform's own ad id (string; Facebook ids are numeric, Snapchat ids are UUIDs). | not_null |
| `ad_name` | varchar | Ad / creative name. |  |
| `ad_status` | varchar | Delivery status (ACTIVE, PAUSED, ARCHIVED, DELETED). NULL for Snapchat, which exposes no status. |  |
| `source_ad_group_id` | varchar | The platform's ad group (ad set) id. |  |
| `ad_group_name` | varchar | Ad group name. |  |
| `source_campaign_id` | varchar | The platform's own campaign id. |  |
| `campaign_name` | varchar | Campaign name as used on the platform. |  |
| `source_account_id` | varchar | The platform's ad account id. |  |
| `account_name` | varchar | Ad account name. NULL for Snapchat (no account table in the extract). |  |
| `currency_code` | varchar | ISO currency of `spend`. | not_null, relationships |
| `spend` | decimal(18,6) | Money spent, in the **native currency** of the ad account (`currency_code`). Not additive across currencies: Facebook has EUR and USD accounts. Use `spend_eur` to add or compare spend across accounts or platforms. | accepted_range, not_null |
| `spend_eur` | decimal(18,6) | Spend converted to EUR with the rate in the `fx_rates_to_eur` seed (`spend x rate_to_eur`). Additive across accounts and platforms. The USD rate is currently a placeholder (see the seed description). | accepted_range, not_null |
| `impressions` | bigint | Number of times ads were shown. NULL means the platform did not report a value (unknown), which is different from 0. | accepted_range |
| `clicks` | bigint | Number of clicks on ads. NULL means the platform did not report a value (unknown), which is different from 0. Roughly a quarter of Facebook rows have no click value. | accepted_range |

### `rpt_marketing_campaign_daily`

Campaign performance by day. **Grain: one row per report date x platform x campaign x currency.** Use this for "spend / impressions / clicks by campaign", "top campaigns" and "performance over time". CTR, CPC and CPM are computed from sums over rows where inputs were reported, and are NULL (not 0) when the denominator is zero. The `*_where_*` columns let you re-aggregate without averaging ratios.

*Materialization:* `table`

| Column | Type | Description | Tests |
|---|---|---|---|
| `report_date` | date | Calendar date. | not_null |
| `platform` | varchar | Advertising platform. | accepted_values, not_null |
| `campaign_key` | varchar | Surrogate key of platform + campaign id. | not_null |
| `source_campaign_id` | varchar | The platform's own campaign id. |  |
| `campaign_name` | varchar | Campaign name. |  |
| `currency_code` | varchar | Currency of `spend` and of `cpc` / `cpm`. | not_null |
| `active_ads` | bigint | Number of distinct ads that reported performance that day. |  |
| `spend` | decimal(38,6) | Money spent, in the **native currency** of the ad account (`currency_code`). Not additive across currencies: Facebook has EUR and USD accounts. Use `spend_eur` to add or compare spend across accounts or platforms. | accepted_range |
| `spend_eur` | decimal(38,6) | Spend converted to EUR with the rate in the `fx_rates_to_eur` seed (`spend x rate_to_eur`). Additive across accounts and platforms. The USD rate is currently a placeholder (see the seed description). |  |
| `impressions` | hugeint | Number of times ads were shown. NULL means the platform did not report a value (unknown), which is different from 0. |  |
| `clicks` | hugeint | Number of clicks on ads. NULL means the platform did not report a value (unknown), which is different from 0. Roughly a quarter of Facebook rows have no click value. |  |
| `spend_where_clicks_reported` | decimal(38,6) | Additive building block for recomputing ratio metrics after a further roll-up. Sum these columns first, then divide: CTR = clicks_where_both_reported / impressions_where_both_reported; CPC = spend_where_clicks_reported / clicks; CPM = spend_where_impressions_reported / impressions x 1000 (and the `_eur` variants). |  |
| `spend_eur_where_clicks_reported` | decimal(38,6) | Additive building block for recomputing ratio metrics after a further roll-up. Sum these columns first, then divide: CTR = clicks_where_both_reported / impressions_where_both_reported; CPC = spend_where_clicks_reported / clicks; CPM = spend_where_impressions_reported / impressions x 1000 (and the `_eur` variants). |  |
| `spend_where_impressions_reported` | decimal(38,6) | Additive building block for recomputing ratio metrics after a further roll-up. Sum these columns first, then divide: CTR = clicks_where_both_reported / impressions_where_both_reported; CPC = spend_where_clicks_reported / clicks; CPM = spend_where_impressions_reported / impressions x 1000 (and the `_eur` variants). |  |
| `spend_eur_where_impressions_reported` | decimal(38,6) | Additive building block for recomputing ratio metrics after a further roll-up. Sum these columns first, then divide: CTR = clicks_where_both_reported / impressions_where_both_reported; CPC = spend_where_clicks_reported / clicks; CPM = spend_where_impressions_reported / impressions x 1000 (and the `_eur` variants). |  |
| `clicks_where_both_reported` | hugeint | Additive building block for recomputing ratio metrics after a further roll-up. Sum these columns first, then divide: CTR = clicks_where_both_reported / impressions_where_both_reported; CPC = spend_where_clicks_reported / clicks; CPM = spend_where_impressions_reported / impressions x 1000 (and the `_eur` variants). |  |
| `impressions_where_both_reported` | hugeint | Additive building block for recomputing ratio metrics after a further roll-up. Sum these columns first, then divide: CTR = clicks_where_both_reported / impressions_where_both_reported; CPC = spend_where_clicks_reported / clicks; CPM = spend_where_impressions_reported / impressions x 1000 (and the `_eur` variants). |  |
| `ctr` | double | **Click-through rate** = `clicks / impressions`, as a fraction (0.012 = 1.2%). Computed from summed values over rows where both clicks and impressions were reported. NULL when there are zero impressions. Never average this column across rows: re-aggregate with `clicks_where_both_reported / impressions_where_both_reported`. | accepted_range |
| `cpc` | double | **Cost per click** = `spend / clicks`, in the account currency. Only spend from rows where clicks were reported is used, so missing click data does not inflate it. NULL when there are zero clicks. Never average this column across rows. | accepted_range |
| `cpc_eur` | double | **Cost per click in EUR** = `spend_eur / clicks`. Use this to compare platforms or accounts with different currencies. |  |
| `cpm` | double | **Cost per mille (1,000 impressions)** = `spend / impressions x 1000`, in the account currency. Only spend from rows where impressions were reported is used. NULL when there are zero impressions. Never average this column across rows. | accepted_range |
| `cpm_eur` | double | **Cost per 1,000 impressions in EUR** = `spend_eur / impressions x 1000`. Use this to compare platforms or accounts with different currencies. |  |

### `rpt_marketing_platform_monthly`

Platform comparison by month. **Grain: one row per calendar month x platform.** Money is in EUR only (platforms bill in different currencies). Use this for "compare Facebook and Snapchat spend", "which platform got more clicks" and month-over-month trends. Note: Snapchat sample data covers 2024 and Facebook sample data covers 2025, so the two platforms do not share a month in the sample data.

*Materialization:* `table`

| Column | Type | Description | Tests |
|---|---|---|---|
| `report_month` | date | First day of the calendar month. | not_null |
| `platform` | varchar | Advertising platform. | accepted_values, not_null |
| `active_campaigns` | bigint | Number of distinct campaigns that reported performance in the month. |  |
| `active_ads` | bigint | Number of distinct ads that reported performance in the month. |  |
| `spend_eur` | decimal(38,6) | Spend converted to EUR with the rate in the `fx_rates_to_eur` seed (`spend x rate_to_eur`). Additive across accounts and platforms. The USD rate is currently a placeholder (see the seed description). | accepted_range |
| `impressions` | hugeint | Number of times ads were shown. NULL means the platform did not report a value (unknown), which is different from 0. |  |
| `clicks` | hugeint | Number of clicks on ads. NULL means the platform did not report a value (unknown), which is different from 0. Roughly a quarter of Facebook rows have no click value. |  |
| `spend_eur_where_clicks_reported` | decimal(38,6) | Additive building block for recomputing ratio metrics after a further roll-up. Sum these columns first, then divide: CTR = clicks_where_both_reported / impressions_where_both_reported; CPC = spend_where_clicks_reported / clicks; CPM = spend_where_impressions_reported / impressions x 1000 (and the `_eur` variants). |  |
| `spend_eur_where_impressions_reported` | decimal(38,6) | Additive building block for recomputing ratio metrics after a further roll-up. Sum these columns first, then divide: CTR = clicks_where_both_reported / impressions_where_both_reported; CPC = spend_where_clicks_reported / clicks; CPM = spend_where_impressions_reported / impressions x 1000 (and the `_eur` variants). |  |
| `clicks_where_both_reported` | hugeint | Additive building block for recomputing ratio metrics after a further roll-up. Sum these columns first, then divide: CTR = clicks_where_both_reported / impressions_where_both_reported; CPC = spend_where_clicks_reported / clicks; CPM = spend_where_impressions_reported / impressions x 1000 (and the `_eur` variants). |  |
| `impressions_where_both_reported` | hugeint | Additive building block for recomputing ratio metrics after a further roll-up. Sum these columns first, then divide: CTR = clicks_where_both_reported / impressions_where_both_reported; CPC = spend_where_clicks_reported / clicks; CPM = spend_where_impressions_reported / impressions x 1000 (and the `_eur` variants). |  |
| `ctr` | double | **Click-through rate** = `clicks / impressions`, as a fraction (0.012 = 1.2%). Computed from summed values over rows where both clicks and impressions were reported. NULL when there are zero impressions. Never average this column across rows: re-aggregate with `clicks_where_both_reported / impressions_where_both_reported`. | accepted_range |
| `cpc_eur` | double | **Cost per click in EUR** = `spend_eur / clicks`. Use this to compare platforms or accounts with different currencies. |  |
| `cpm_eur` | double | **Cost per 1,000 impressions in EUR** = `spend_eur / impressions x 1000`. Use this to compare platforms or accounts with different currencies. |  |

## Intermediate (silver)

### `int_facebook_ads__performance`

Facebook daily ad stats enriched with ad, ad group, campaign and account attributes. **Grain: one row per ad per day.** Ephemeral (inlined into `int_marketing_ads`), so it has no table in the warehouse; its integrity is covered by the tests on `int_marketing_ads`.

*Materialization:* `ephemeral`

| Column | Type | Description | Tests |
|---|---|---|---|

### `int_marketing_ads`

Facebook and Snapchat on one schema. **Grain: one row per platform x ad x report date x country** (`performance_key`). This is where platform differences are normalized: shared column names, platform-scoped surrogate keys, explicit `UNSPECIFIED` country for Facebook, and EUR conversion. A uniqueness test on `performance_key` here catches join fan-out before it reaches the marts.

*Materialization:* `view`

| Column | Type | Description | Tests |
|---|---|---|---|
| `performance_key` | varchar | Surrogate key of platform + source_ad_id + report_date + country_code. | not_null, unique |
| `ad_key` | varchar |  |  |
| `campaign_key` | varchar |  |  |
| `platform` | varchar | Advertising platform. | accepted_values, not_null |
| `report_date` | date |  |  |
| `country_code` | varchar |  |  |
| `source_ad_id` | varchar |  |  |
| `ad_name` | varchar |  |  |
| `ad_status` | varchar |  |  |
| `source_ad_group_id` | varchar |  |  |
| `ad_group_name` | varchar |  |  |
| `source_campaign_id` | varchar |  |  |
| `campaign_name` | varchar |  |  |
| `source_account_id` | varchar |  |  |
| `account_name` | varchar |  |  |
| `currency_code` | varchar |  |  |
| `spend` | decimal(18,6) |  |  |
| `spend_eur` | decimal(18,6) |  |  |
| `impressions` | bigint |  |  |
| `clicks` | bigint |  |  |

### `int_snapchat_ads__performance`

Snapchat daily ad stats enriched with ad, ad group and campaign attributes. **Grain: one row per ad per day per country.** Ephemeral (inlined into `int_marketing_ads`).

*Materialization:* `ephemeral`

| Column | Type | Description | Tests |
|---|---|---|---|

## Staging (silver)

### `stg_facebook_ads__accounts`

Facebook ad accounts, latest version per account. **Grain: one row per `account_id`.**

*Materialization:* `view`

| Column | Type | Description | Tests |
|---|---|---|---|
| `account_id` | varchar | Facebook ad account id. | not_null, relationships, unique |
| `account_name` | varchar | Account name. |  |
| `currency_code` | varchar | ISO currency of all spend reported for the account. Must have a rate in `fx_rates_to_eur`. | not_null, relationships |
| `created_at` | timestamp | When the account was created. |  |
| `updated_at` | timestamp | When the account was last changed. |  |

### `stg_facebook_ads__ad_groups`

Facebook ad groups, latest version per group. **Grain: one row per `ad_group_id`.**

*Materialization:* `view`

| Column | Type | Description | Tests |
|---|---|---|---|
| `ad_group_id` | varchar | Facebook ad group id. | not_null, relationships, unique |
| `ad_group_name` | varchar | Ad group name. |  |
| `updated_at` | timestamp | When the ad group was last changed. |  |

### `stg_facebook_ads__ad_stats`

Typed daily Facebook ad performance. **Grain: one row per ad per day (`ad_id`, `report_date`).** Spend is in the owning account's currency. Impressions/clicks that the platform marked 'null' are NULL here (unknown), not 0.

*Materialization:* `view`

| Column | Type | Description | Tests |
|---|---|---|---|
| `ad_id` | varchar | Facebook ad id. | not_null, relationships |
| `account_id` | varchar | Facebook ad account that owns the ad (carries the currency). | not_null, relationships |
| `report_date` | date | Date the performance relates to. | not_null |
| `spend` | decimal(18,6) | Spend in the account currency. Never negative. | accepted_range, not_null |
| `impressions` | bigint | Impressions served. NULL when not reported. | accepted_range |
| `clicks` | bigint | Clicks. NULL when not reported. | accepted_range |

### `stg_facebook_ads__ads`

Facebook ads, latest version per ad. **Grain: one row per `ad_id`.**

*Materialization:* `view`

| Column | Type | Description | Tests |
|---|---|---|---|
| `ad_id` | varchar | Facebook ad id. | not_null, relationships, unique |
| `campaign_id` | varchar | Campaign the ad belongs to. | relationships |
| `ad_group_id` | varchar | Ad group (ad set) the ad belongs to. | relationships |
| `account_id` | varchar | Ad account that owns the ad. |  |
| `ad_name` | varchar | Ad / creative name. |  |
| `ad_status` | varchar | Upper-cased delivery status. | accepted_values |
| `updated_at` | timestamp | When the ad was last changed in Facebook. |  |

### `stg_facebook_ads__campaigns`

Facebook campaigns, latest version per campaign. **Grain: one row per `campaign_id`.**

*Materialization:* `view`

| Column | Type | Description | Tests |
|---|---|---|---|
| `campaign_id` | varchar | Facebook campaign id. | not_null, relationships, unique |
| `campaign_name` | varchar | Campaign name. |  |
| `updated_at` | timestamp | When the campaign was last changed. |  |

### `stg_snapchat_ads__ad_groups`

Snapchat ad groups reduced to the latest version. **Grain: one row per `ad_group_id`.** The source holds several versions for some ad groups; keeping them all would duplicate fact rows.

*Materialization:* `view`

| Column | Type | Description | Tests |
|---|---|---|---|
| `ad_group_id` | varchar | Snapchat ad group id (UUID). | not_null, relationships, unique |
| `campaign_id` | varchar | Campaign the ad group belongs to. | not_null, relationships |
| `ad_group_name` | varchar | Ad group name. |  |
| `updated_at` | timestamp | When this version of the ad group was written. |  |

### `stg_snapchat_ads__ad_stats`

Typed daily Snapchat ad performance. **Grain: one row per ad per day per country (`ad_id`, `report_date`, `country_code`).** `ad_id` is Snapchat's `ad_detail_id`. Spend is in `currency_code`. Clicks marked 'null' by the platform are NULL (unknown), not 0.

*Materialization:* `view`

| Column | Type | Description | Tests |
|---|---|---|---|
| `ad_id` | varchar | Snapchat ad id (UUID). | not_null, relationships |
| `report_date` | date | Date the performance relates to. | not_null |
| `country_code` | varchar | Upper-case ISO country code of the delivery breakdown. | not_null |
| `currency_code` | varchar | ISO currency of `spend`. Must have a rate in `fx_rates_to_eur`. | not_null, relationships |
| `spend` | decimal(18,6) | Spend in `currency_code`. Never negative. | accepted_range, not_null |
| `impressions` | bigint | Impressions served. | accepted_range |
| `clicks` | bigint | Clicks. NULL when not reported. | accepted_range |

### `stg_snapchat_ads__ads`

Snapchat ads, latest version per ad. **Grain: one row per `ad_id`.** No status column exists in the source.

*Materialization:* `view`

| Column | Type | Description | Tests |
|---|---|---|---|
| `ad_id` | varchar | Snapchat ad id (UUID). | not_null, relationships, unique |
| `ad_group_id` | varchar | Ad group the ad belongs to. About 12% of ads point to ad groups missing from the extract (none of them have performance data), hence the warn-level severity. | relationships |
| `ad_name` | varchar | Ad / creative name. |  |
| `updated_at` | timestamp | When the ad was last changed (`ad_detail_updated_at` in the source). |  |

### `stg_snapchat_ads__campaigns`

Snapchat campaigns. **Grain: one row per `campaign_id`.**

*Materialization:* `view`

| Column | Type | Description | Tests |
|---|---|---|---|
| `campaign_id` | varchar | Snapchat campaign id (UUID). | not_null, relationships, unique |
| `account_id` | varchar | Snapchat ad account id (UUID). There is no account table in the extract. | not_null |
| `campaign_name` | varchar | Campaign name. |  |

## Reference data (seed)

### `fx_rates_to_eur`

Fixed currency conversion rates to EUR, the reporting currency. Used to compute `spend_eur` so Facebook (EUR and USD accounts) and Snapchat (EUR) spend can be compared and summed. The USD rate is a PLACEHOLDER: replace it with the finance-approved rate (or swap this seed for a dated rates table and join on report_date) before treating spend_eur as official.

| Column | Type | Description | Tests |
|---|---|---|---|
| `currency_code` | varchar | ISO 4217 currency code. | not_null, relationships, unique |
| `rate_to_eur` | decimal(18,6) | Multiply an amount in `currency_code` by this rate to get EUR. | accepted_range, not_null |
| `rate_note` | varchar | Where the rate comes from / caveats. |  |

## Raw sources (bronze)

All raw columns are strings; typing happens in staging.

### `facebook_ads.accounts`

Ad account dimension. One row per account, carries the account currency. Source file: new_acccount_de_randomized.csv.

| Column | Description |
|---|---|
| `account_id` | Facebook ad account id. |

### `facebook_ads.ad_groups`

Ad group (ad set) dimension. One row per ad group. Source file: new_adgroup_de_randomized.csv.

| Column | Description |
|---|---|
| `ad_group_id` | Facebook ad group id. |

### `facebook_ads.ad_stats`

Daily ad performance. One row per ad per day, in the currency of the owning account. Source file: ads_stats.csv. `ad_impressions` and `ad_clicks` contain the literal text 'null' when the platform did not report a value.

| Column | Description |
|---|---|
| `ad_id` | Facebook ad id (13-18 digit numeric string). |
| `account_id` | Facebook ad account id that owns the ad. |
| `ad_spend` | Spend for the day in the account's currency. |
| `ad_impressions` | Impressions as text; may be the string 'null'. |
| `ad_clicks` | Clicks as text; may be the string 'null'. |
| `ad_date` | Reporting date (YYYY-MM-DD). |

### `facebook_ads.ads`

Ad dimension. One row per ad. Source file: new_ads_de_randomized.csv.

| Column | Description |
|---|---|
| `ad_id` | Facebook ad id. |

### `facebook_ads.campaigns`

Campaign dimension. One row per campaign. Source file: new_campaign_de_randomized.csv.

| Column | Description |
|---|---|
| `campaign_id` | Facebook campaign id. |

### `snapchat_ads.ad_groups`

Ad group history. Contains more than one version of some ad groups (same ad_group_id, different `ad_group_updated_at`), so it must be reduced to the latest version before joining. Source file: snapchat_ads_adgroup_history_new_ad_group_names.csv.

| Column | Description |
|---|---|
| `_surrogate_key` | Source-generated hash, unique per ad group version. |

### `snapchat_ads.ad_stats`

Daily ad performance. One row per ad per day per country (ad_detail_id, ad_date, ad_country). Source file: snapchat_ads_stats.csv. `ad_clicks` contains the literal text 'null' when not reported. Spend is in plain currency units (not micro-currency).

| Column | Description |
|---|---|
| `ad_detail_id` | Snapchat ad id (UUID). Joins to ad_history `ad_id`. |
| `ad_currency_code` | ISO currency code of the spend value. |
| `ad_country` | Lower-case ISO country code the delivery is broken down by. |
| `ad_spend` | Spend for the day/country in `ad_currency_code`. |
| `ad_impressions` | Impressions. |
| `ad_clicks` | Clicks as text; may be the string 'null'. |
| `ad_date` | Reporting date (YYYY-MM-DD). |
| `data_src` | Constant 'snapchat_ads'. |

### `snapchat_ads.ads`

Ad history. One row per ad. Source file: snapchat_ads_ad_history_new_ad_names.csv.

| Column | Description |
|---|---|
| `ad_id` | Snapchat ad id (UUID). |

### `snapchat_ads.campaigns`

Campaign history. One row per campaign, links campaigns to an account id. Source file: snapchat_ads_campaign_history_new_campaign_names.csv.

| Column | Description |
|---|---|
| `campaign_id` | Snapchat campaign id (UUID). |
