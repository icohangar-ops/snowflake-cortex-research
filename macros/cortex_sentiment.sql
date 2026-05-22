{% macro cortex_sentiment(text_col, model='mistral-large') %}

    SNOWFLAKE.CORTEX.SENTIMENT({{ text_col }})

{% endmacro %}
