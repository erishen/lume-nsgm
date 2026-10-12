CREATE TABLE IF NOT EXISTS "{{ctrl}}" (
{{#each fields as f}}  "{{f.name}}" {{f.type_sql}}{{#if f.auto}} PRIMARY KEY AUTOINCREMENT{{/if}}{{#if f.not_null}} NOT NULL{{/if}}{{#if f.default}}{{f.default}}{{/if}},
{{/each}}
);
