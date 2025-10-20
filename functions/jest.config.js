module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  testMatch: ['**/*.test.ts'],
  moduleFileExtensions: ['ts', 'js', 'json'],
  globals: {
    'ts-jest': {
      tsconfig: './tsconfig.test.json'
    }
  },
  clearMocks: true,
  transformIgnorePatterns: ['/node_modules/']
};
