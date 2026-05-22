{% macro cortex_embeddings(text_col, model='snowflake-arctic-embed-m') %}

    SNOWFLAKE.CORTEX.EMBED_TEXT('{{ model }}', {{ text_col }})

{% endmacro %}
