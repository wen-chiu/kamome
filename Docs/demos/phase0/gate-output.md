# Phase 0 gate run — 2026-07-12, dev Mac (Xcode 15.4, iPhone 15 simulator, iOS 17.5)

All three §7 Phase 0 gate criteria, actual command output.

## 1. `xcodegen generate`

    ⚙️  Generating plists...
    ⚙️  Generating project...
    ⚙️  Writing project...
    Created project at /Users/chenwenqiu/Kamome/Kamome.xcodeproj

## 2. `xcodebuild -scheme Kamome test -destination 'platform=iOS Simulator,name=iPhone 15'`

9 tests, 0 failures — app tests (String Catalog zh-Hant/en, bundled config)
plus KamomeCore package tests (schema v1, config loader, round-trip):

    Test Case '-[KamomeTests.AppConfigTests testBundledConfigLoads]' passed (0.003 seconds).
    Test Case '-[KamomeTests.LocalizationTests testSampleStringResolvesInDevelopmentLanguage]' passed (0.002 seconds).
    Test Case '-[KamomeTests.LocalizationTests testSampleStringResolvesInEnglish]' passed (0.001 seconds).
    Test Case '-[KamomeCoreTests.ConfigLoaderTests testGarbageInputFailsLoudly]' passed (0.003 seconds).
    Test Case '-[KamomeCoreTests.ConfigLoaderTests testLoadsShippedConfigWithSpecDefaults]' passed (0.002 seconds).
    Test Case '-[KamomeCoreTests.ConfigLoaderTests testMissingKeyFailsLoudlyNamingTheKey]' passed (0.002 seconds).
    Test Case '-[KamomeCoreTests.SchemaTests testMigrationsAreForwardOnlyAndComplete]' passed (0.006 seconds).
    Test Case '-[KamomeCoreTests.SchemaTests testMigrationToV1CreatesAllTablesAndIndex]' passed (0.001 seconds).
    Test Case '-[KamomeCoreTests.TrackpointRoundTripTests testFiftyThousandTrackpointsRoundTripUnderTwoSeconds]' passed (1.237 seconds).
    ** TEST SUCCEEDED **

Gate criterion "insert/read 50k trackpoints < 2 s in-memory": 1.237 s.

## 3. `swiftlint`

    Done linting! Found 0 violations, 0 serious in 10 files.

Local destination is iPhone 15 (Xcode 15.4 has no iPhone 16 device type);
CI runs the same scheme against iPhone 16 on its Xcode 16 runner.
