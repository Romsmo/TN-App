// Screens read the safe-area insets; the tests have no native provider, so the library's own mock stands in.
jest.mock('react-native-safe-area-context', () => require('react-native-safe-area-context/jest/mock').default);
