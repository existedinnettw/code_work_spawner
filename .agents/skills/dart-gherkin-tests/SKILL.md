---
name: dart-gherkin-tests
description: Use when creating or editing Dart tests in this repo. Enforces the repository's required Gherkin-style doc comments for `group(...)` and `test(...)`, plus inline Given/When/Then comments inside test bodies.
---

# Dart Gherkin Tests

Use this skill for any new or modified file under `test/`.

## Required format

Every `group(...)` must be preceded by a Gherkin doc block:

```dart
/// ```gherkin
/// Feature: AppConfig loading
///
///   As a user of the Code Work Spawner
///   I want the app configuration to correctly merge defaults with project-specific overrides
///   So that I can specify common settings once and customize only what differs for each project
/// ```
group('AppConfig.load', () {
```

Every `test(...)` must be preceded by a Gherkin doc block:

```dart
  /// ```gherkin
  /// Scenario: Merge defaults with project overrides
  ///   Given AO style config with shared defaults and one project override
  ///   When loading the app config from disk
  ///   Then the project keeps inherited defaults that were not overridden
  ///   And the project-specific prompt replaces the shared prompt
  /// ```
  test('Merge defaults with project overrides', () async {
```

Inside the test body, use inline phase comments:

```dart
    // Given AO style config with shared defaults and one project override.
    ...

    // When loading the app config from disk.
    ...

    // Then the project keeps inherited defaults that were not overridden.
    ...

    // And the project-specific prompt replaces the shared prompt.
    ...
```

## Rules

- Do add `Feature:` and `Scenario:` only in doc comments.
- Do keep runtime `group(...)` names code-oriented.
- Do keep runtime `test(...)` names as the scenario title only.
- Do use inline `// Given`, `// When`, and `// Then` comments in every test body.
- Do use `// And` when a scenario has multiple assertions or setup steps.
- Do not put `Feature:` in the `group(...)` string.
- Do not put `Scenario:` in the `test(...)` string.
- Do not add tests under `test/` without the required Gherkin doc-comment blocks.

## Checklist

Before finishing test work in this repo:

1. Confirm every `group(...)` has a `Feature` doc block directly above it.
2. Confirm every `test(...)` has a `Scenario` doc block directly above it.
3. Confirm every test body has `Given`, `When`, and `Then` inline comments.
4. Run `dart run tool/validate_gherkin_test_format.dart`.
