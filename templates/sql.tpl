CREATE DATABASE IF NOT EXISTS {{db}} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

use {{db}};

CREATE TABLE IF NOT EXISTS `{{ctrl}}` (
{{#each fields as f}}  `{{f.name}}` {{f.type_sql}}{{#if f.not_null}} NOT NULL{{/if}}{{#if f.auto}} AUTO_INCREMENT{{/if}}{{#if f.comment}} COMMENT '{{f.comment}}'{{/if}},
{{/each}}  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4;