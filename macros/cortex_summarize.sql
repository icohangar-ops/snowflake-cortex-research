{% macro cortex_summarize(text_col, model='mistral-large') %}

    SNOWFLAKE.CORTEX.SUMMARIZE({{ text_col }})

{% endmacro %}
