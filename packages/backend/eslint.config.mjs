import tsParser from '@typescript-eslint/parser';
import tsPlugin from '@typescript-eslint/eslint-plugin';

export default [
  {
    ignores: ['dist/**', 'drizzle/**', 'node_modules/**'],
  },
  {
    files: ['src/**/*.ts'],
    languageOptions: {
      parser: tsParser,
      parserOptions: {
        project: false,
        sourceType: 'module',
        ecmaVersion: 'latest',
      },
    },
    plugins: {
      '@typescript-eslint': tsPlugin,
    },
    rules: {
      'no-unused-vars': 'off',
      '@typescript-eslint/no-unused-vars': ['warn', { argsIgnorePattern: '^_' }],
      '@typescript-eslint/consistent-type-imports': 'warn',
      // Tenant isolation guard: every business query MUST call tenantFilter().
      // If you see this warning, add tenantFilter(table.tenantId, tenantId) to your WHERE clause.
      // Reference: src/services/tenant.service.ts
      'no-restricted-syntax': [
        'warn',
        {
          selector:
            "CallExpression[callee.type='MemberExpression'][callee.property.name='findMany']:not(:has(Identifier[name='tenantFilter']))",
          message:
            'Business queries must include tenantFilter(). See tenant.service.ts for helpers.',
        },
        {
          selector:
            "CallExpression[callee.type='MemberExpression'][callee.property.name='findFirst']:not(:has(Identifier[name='tenantFilter']))",
          message:
            'Business queries must include tenantFilter(). See tenant.service.ts for helpers.',
        },
      ],
    },
  },
];
