const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

module.exports = {
    ...jestConfig,
    moduleNameMapper: {
        '^lightning/accApi$': '<rootDir>/force-app/test/jest-mocks/lightning/accApi',
        ...jestConfig.moduleNameMapper
    },
    modulePathIgnorePatterns: ['<rootDir>/.localdevserver']
};
