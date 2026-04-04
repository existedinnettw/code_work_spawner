import 'dart:io';

import 'package:code_work_spawner/code_work_spawner.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  /// ```gherkin
  /// Feature: AppConfig loading
  ///
  ///   As a user of the Code Work Spawner
  ///   I want the app configuration to correctly merge defaults with project-specific overrides
  ///   So that I can specify common settings once and customize only what differs for each project
  /// ```
  group('AppConfig.load', () {
    /// ```gherkin
    /// Scenario: Merge defaults with project overrides
    ///   Given AO style config with shared defaults and one project override
    ///   When loading the app config from disk
    ///   Then the project keeps inherited defaults that were not overridden
    ///   And the project-specific prompt replaces the shared prompt
    /// ```
    test('Merge defaults with project overrides', () async {
      // Given AO style config with shared defaults and one project override.
      final tempDir = await Directory.systemTemp.createTemp('cws-config-');
      final configFile = File(p.join(tempDir.path, 'agent-orchestrator.yaml'));
      await configFile.writeAsString('''
defaults:
  issueAssistant:
    enabled: true
    pollInterval: 5m
    mentionTriggers: ["@helper"]
    prompt: "default {{repo}}"
    commentPrefixTemplate: "> default prefix {{gh_login}}"
    commentFooterTemplate: "default footer {{issue_number}}"
    responders:
      - id: fallback
        command: responder
projects:
  sample:
    repo: owner/sample
    path: ${tempDir.path}
    defaultBranch: main
    issueAssistant:
      prompt: "project {{project_key}}"
''');

      // When loading the app config from disk.
      final config = await AppConfig.load(configFile.path);

      // Then the project keeps inherited defaults that were not overridden.
      expect(config.projects['sample'], isNotNull);
      expect(config.projects['sample']!.repoSlug.owner, 'owner');
      expect(config.projects['sample']!.repoSlug.name, 'sample');
      expect(config.projects['sample']!.issueAssistant.mentionTriggers, [
        '@helper',
      ]);
      expect(
        config.projects['sample']!.issueAssistant.responders.single.id,
        'fallback',
      );

      // And the project-specific prompt replaces the shared prompt.
      expect(
        config.projects['sample']!.issueAssistant.prompt,
        'project {{project_key}}',
      );
    });

    /// ```gherkin
    /// Scenario: Use exported default automation comment templates
    ///   Given an orchestrator config that relies on default issue assistant comment templates
    ///   When loading the app config from disk
    ///   Then the assistant uses the exported default prefix and footer templates
    /// ```
    test('Use exported default automation comment templates', () async {
      // Given an orchestrator config that relies on default issue assistant comment templates.
      final tempDir = await Directory.systemTemp.createTemp(
        'cws-default-templates-',
      );
      final configFile = File(p.join(tempDir.path, 'agent-orchestrator.yaml'));
      await configFile.writeAsString('''
projects:
  sample:
    repo: owner/sample
    path: ${tempDir.path}
''');

      // When loading the app config from disk.
      final config = await AppConfig.load(configFile.path);

      // Then the assistant uses the exported default prefix and footer templates.
      expect(
        config.projects['sample']!.issueAssistant.commentPrefixTemplate,
        defaultCommentPrefixTemplate,
      );
      expect(
        config.projects['sample']!.issueAssistant.commentFooterTemplate,
        defaultCommentFooterTemplate,
      );
      expect(
        config.projects['sample']!.issueAssistant.pollInterval,
        const Duration(seconds: 30),
      );
      expect(config.projects['sample']!.issueAssistant.maxConcurrentIssues, 3);
    });

    /// ```gherkin
    /// Scenario: Override visible comment templates per project
    ///   Given AO style config with shared defaults and project-specific comment templates
    ///   When loading the app config from disk
    ///   Then the project-specific comment templates replace the shared defaults
    /// ```
    test('Override visible comment templates per project', () async {
      // Given AO style config with shared defaults and project-specific comment templates.
      final tempDir = await Directory.systemTemp.createTemp(
        'cws-comment-template-',
      );
      final configFile = File(p.join(tempDir.path, 'agent-orchestrator.yaml'));
      await configFile.writeAsString('''
defaults:
  issueAssistant:
    commentPrefixTemplate: "> default prefix"
    commentFooterTemplate: "default footer"
projects:
  sample:
    repo: owner/sample
    path: ${tempDir.path}
    issueAssistant:
      commentPrefixTemplate: ""
      commentFooterTemplate: "_project footer_"
''');

      // When loading the app config from disk.
      final config = await AppConfig.load(configFile.path);

      // Then the project-specific comment templates replace the shared defaults.
      expect(
        config.projects['sample']!.issueAssistant.commentPrefixTemplate,
        '',
      );
      expect(
        config.projects['sample']!.issueAssistant.commentFooterTemplate,
        '_project footer_',
      );
    });

    /// ```gherkin
    /// Scenario: Normalize legacy codex json flag
    ///   Given an orchestrator config that still uses the legacy codex --json-output flag
    ///   When loading the app config from disk
    ///   Then the responder args are normalized to the current codex --json flag
    /// ```
    test('Normalize legacy codex json flag', () async {
      // Given an orchestrator config that still uses the legacy codex --json-output flag.
      final tempDir = await Directory.systemTemp.createTemp('cws-codex-args-');
      final configFile = File(p.join(tempDir.path, 'agent-orchestrator.yaml'));
      await configFile.writeAsString('''
defaults:
  issueAssistant:
    responders:
      - id: codex
        command: codex
        args: ["exec", "--json-output"]
projects:
  sample:
    repo: owner/sample
    path: ${tempDir.path}
''');

      // When loading the app config from disk.
      final config = await AppConfig.load(configFile.path);

      // Then the responder args are normalized to the current codex --json flag.
      expect(config.projects['sample']!.issueAssistant.responders.single.args, [
        'exec',
        '--json',
      ]);
    });

    /// ```gherkin
    /// Scenario: Load AO subset config with shared worktree root
    ///   Given an AO style shortcut config with dataDir, worktreeDir, and project defaults
    ///   When loading the app config from disk
    ///   Then the app exposes the configured data and worktree directories
    ///   And each project inherits the supported shared defaults
    /// ```
    test('Load AO subset config with shared worktree root', () async {
      // Given an AO style shortcut config with dataDir, worktreeDir, and project defaults.
      final tempDir = await Directory.systemTemp.createTemp('cws-ao-subset-');
      final configFile = File(p.join(tempDir.path, 'agent-orchestrator.yaml'));
      await configFile.writeAsString('''
dataDir: ~/.agent-orchestrator
worktreeDir: ~/.worktrees
defaults:
  defaultBranch: trunk
  sessionPrefix: ao
projects:
  sample:
    repo: owner/sample
    path: ${tempDir.path}
''');

      // When loading the app config from disk.
      final config = await AppConfig.load(configFile.path);

      // Then the app exposes the configured data and worktree directories.
      expect(
        config.dataDir,
        p.join(Platform.environment['HOME']!, '.agent-orchestrator'),
      );
      expect(
        config.worktreeDir,
        p.join(Platform.environment['HOME']!, '.worktrees'),
      );

      // And each project inherits the supported shared defaults.
      expect(config.projects['sample'], isNotNull);
      expect(config.projects['sample']!.defaultBranch, 'trunk');
      expect(config.projects['sample']!.sessionPrefix, 'ao');
      expect(config.projects['sample']!.issueAssistant.enabled, isTrue);
    });

    /// ```gherkin
    /// Scenario: Reject unsupported AO fields
    ///   Given an AO style config that includes an unsupported field
    ///   When loading the app config from disk
    ///   Then loading fails with a clear config error
    /// ```
    test('Reject unsupported AO fields', () async {
      // Given an AO style config that includes an unsupported field.
      final tempDir = await Directory.systemTemp.createTemp('cws-ao-invalid-');
      final configFile = File(p.join(tempDir.path, 'agent-orchestrator.yaml'));
      await configFile.writeAsString('''
worktreeDir: ~/.worktrees
projects:
  sample:
    repo: owner/sample
    path: ${tempDir.path}
    tracker:
      plugin: github
''');

      // When loading the app config from disk.
      final load = AppConfig.load(configFile.path);

      // Then loading fails with a clear config error.
      await expectLater(
        load,
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Unsupported config field: projects.sample.tracker'),
          ),
        ),
      );
    });

    /// ```gherkin
    /// Scenario: Reject malformed repository slugs
    ///   Given an orchestrator config whose project repo is not in owner/repo format
    ///   When loading the app config from disk
    ///   Then loading fails with a clear repository slug error
    /// ```
    test('Reject malformed repository slugs', () async {
      // Given an orchestrator config whose project repo is not in owner/repo format.
      final tempDir = await Directory.systemTemp.createTemp(
        'cws-invalid-repo-slug-',
      );
      final configFile = File(p.join(tempDir.path, 'agent-orchestrator.yaml'));
      await configFile.writeAsString('''
projects:
  sample:
    repo: owner
    path: ${tempDir.path}
''');

      // When loading the app config from disk.
      final load = AppConfig.load(configFile.path);

      // Then loading fails with a clear repository slug error.
      await expectLater(
        load,
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Invalid repository slug for projects.sample.repo'),
          ),
        ),
      );
    });
  });
}
