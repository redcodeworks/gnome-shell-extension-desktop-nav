// Dev-only lint configuration for the extension's JavaScript (ESLint 9 or newer, flat config).
// It is never packed into the zip and needs no dependencies: no plugins and no `require`
// of other packages, so `npx eslint` is enough (see `just lint-js`).
//
// Based on the style of the GJS guide (https://gjs.guide/guides/gjs/style-guide.html) and the
// ESLint recommended correctness rules, written from memory WITHOUT access to the guide:
// UNVERIFIED against the official gjs-guide configuration. Style rules are limited to the ones
// the current code already follows.
'use strict';

// Globals GJS provides to every module (besides the ES built-ins).
const gjsGlobals = {
    global: 'readonly',
    imports: 'readonly',
    console: 'readonly',
    log: 'readonly',
    logError: 'readonly',
    print: 'readonly',
    printerr: 'readonly',
    ARGV: 'readonly',
    setTimeout: 'readonly',
    clearTimeout: 'readonly',
    setInterval: 'readonly',
    clearInterval: 'readonly',
    TextDecoder: 'readonly',
    TextEncoder: 'readonly',
    URL: 'readonly',
    URLSearchParams: 'readonly',
    structuredClone: 'readonly',
    queueMicrotask: 'readonly',
};

module.exports = [
    {
        ignores: ['dist/**', 'node_modules/**', '**/*.min.js'],
    },
    {
        files: ['**/*.js'],
        languageOptions: {
            ecmaVersion: 2024,
            sourceType: 'module',
            globals: gjsGlobals,
        },
        linterOptions: {
            reportUnusedDisableDirectives: 'error',
        },
        rules: {
            // correctness (the ESLint recommended set, spelled out)
            'constructor-super': 'error',
            'getter-return': 'error',
            'no-case-declarations': 'error',
            'no-class-assign': 'error',
            'no-cond-assign': 'error',
            'no-const-assign': 'error',
            'no-dupe-args': 'error',
            'no-dupe-class-members': 'error',
            'no-dupe-else-if': 'error',
            'no-dupe-keys': 'error',
            'no-duplicate-case': 'error',
            'no-empty': ['error', {allowEmptyCatch: true}],
            'no-func-assign': 'error',
            'no-import-assign': 'error',
            'no-loss-of-precision': 'error',
            'no-prototype-builtins': 'error',
            'no-redeclare': 'error',
            'no-self-assign': 'error',
            'no-sparse-arrays': 'error',
            'no-this-before-super': 'error',
            'no-undef': 'error',
            'no-unreachable': 'error',
            'no-unsafe-finally': 'error',
            'no-unsafe-negation': 'error',
            'no-unused-vars': ['error', {args: 'after-used', argsIgnorePattern: '^_', caughtErrors: 'none'}],
            'require-yield': 'error',
            'use-isnan': 'error',
            'valid-typeof': 'error',

            // GJS guide style, as far as the code already follows it
            'eqeqeq': ['error', 'smart'],
            'no-var': 'error',
            'prefer-const': 'error',
            'semi': ['error', 'always'],
            'quotes': ['error', 'single', {avoidEscape: true, allowTemplateLiterals: true}],
            'indent': ['error', 4, {
                SwitchCase: 0,
                ignoredNodes: ['TemplateLiteral > *'],
                MemberExpression: 'off',
                flatTernaryExpressions: true,
            }],
            'no-trailing-spaces': 'error',
            'eol-last': 'error',
            'keyword-spacing': 'error',
            'space-before-blocks': 'error',
            'comma-spacing': 'error',
            'no-multi-spaces': ['error', {ignoreEOLComments: true}],
            'max-len': ['warn', {code: 200, ignoreUrls: true, ignoreStrings: true, ignoreTemplateLiterals: true}],
        },
    },
];
