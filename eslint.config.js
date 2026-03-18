const lwcConfig = require('@salesforce/eslint-config-lwc');
const jestPlugin = require('eslint-plugin-jest');

module.exports = [
    {
        ignores: ['coverage/**', 'node_modules/**']
    },
    ...lwcConfig.configs.recommended,
    {
        files: ['**/__tests__/**/*.js'],
        ...jestPlugin.configs['flat/recommended'],
        rules: {
            ...jestPlugin.configs['flat/recommended'].rules,
            'jest/no-untyped-mock-factory': 'off'
        }
    }
];
