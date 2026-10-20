{% docs spend %}
Money spent, in the **native currency** of the ad account (`currency_code`). Not additive across
currencies: Facebook has EUR and USD accounts. Use `spend_eur` to add or compare spend across accounts or platforms.
{% enddocs %}

{% docs spend_eur %}
Spend converted to EUR with the rate in the `fx_rates_to_eur` seed (`spend x rate_to_eur`).
Additive across accounts and platforms. The USD rate is currently a placeholder (see the seed description).
{% enddocs %}

{% docs impressions %}
Number of times ads were shown. NULL means the platform did not report a value (unknown), which is different from 0.
{% enddocs %}

{% docs clicks %}
Number of clicks on ads. NULL means the platform did not report a value (unknown), which is different from 0.
Roughly a quarter of Facebook rows have no click value.
{% enddocs %}

{% docs ctr %}
**Click-through rate** = `clicks / impressions`, as a fraction (0.012 = 1.2%).
Computed from summed values over rows where both clicks and impressions were reported.
NULL when there are zero impressions. Never average this column across rows: re-aggregate with
`clicks_where_both_reported / impressions_where_both_reported`.
{% enddocs %}

{% docs cpc %}
**Cost per click** = `spend / clicks`, in the account currency. Only spend from rows where clicks were
reported is used, so missing click data does not inflate it. NULL when there are zero clicks.
Never average this column across rows.
{% enddocs %}

{% docs cpc_eur %}
**Cost per click in EUR** = `spend_eur / clicks`. Use this to compare platforms or accounts with different currencies.
{% enddocs %}

{% docs cpm %}
**Cost per mille (1,000 impressions)** = `spend / impressions x 1000`, in the account currency. Only spend from rows
where impressions were reported is used. NULL when there are zero impressions. Never average this column across rows.
{% enddocs %}

{% docs cpm_eur %}
**Cost per 1,000 impressions in EUR** = `spend_eur / impressions x 1000`. Use this to compare platforms or accounts with different currencies.
{% enddocs %}

{% docs building_blocks %}
Additive building block for recomputing ratio metrics after a further roll-up. Sum these columns first, then divide:
CTR = clicks_where_both_reported / impressions_where_both_reported; CPC = spend_where_clicks_reported / clicks;
CPM = spend_where_impressions_reported / impressions x 1000 (and the `_eur` variants).
{% enddocs %}
