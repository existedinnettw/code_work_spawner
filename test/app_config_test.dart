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
    ///   Given camelCase config with shared defaults and one project override
    ///   When loading the app config from disk
    ///   Then the project keeps inherited defaults that were not overridden
    ///   And the project-specific prompt replaces the shared prompt
    /// ```
    test('Merge defaults with project overrides', () async {
      // Given camelCase config with shared defaults and one project override.
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
    ///   Given camelCase config with shared defaults and project-specific comment templates
    ///   When loading the app config from disk
    ///   Then the project-specific comment templates replace the shared defaults
    /// ```
    test('Override visible comment templates per project', () async {
      // Given camelCase config with shared defaults and project-specific comment templates.
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
    /// Scenario: Merge notification defaults with project overrides
    ///   Given camelCase config with default notifications and a project-specific notification override
    ///   When loading the app config from disk
    ///   Then the project replaces inherited notifications with its own list
    ///   And notification event enums are parsed from snake_case values
    /// ```
    test('Merge notification defaults with project overrides', () async {
      // Given camelCase config with default notifications and a project-specific notification override.
      final tempDir = await Directory.systemTemp.createTemp(
        'cws-notification-config-',
      );
      final configFile = File(p.join(tempDir.path, 'agent-orchestrator.yaml'));
      await configFile.writeAsString('''
defaults:
  issueAssistant:
    notifications:
      - type: discordWebhook
        enabled: true
        events: ["reply_posted"]
        webhookUrl: https://default.example.test/webhook
projects:
  sample:
    repo: owner/sample
    path: ${tempDir.path}
    issueAssistant:
      notifications:
        - type: discordWebhook
          enabled: true
          events: ["responder_failed", "no_reply"]
          webhookUrl: https://project.example.test/webhook
          username: cws
''');

      // When loading the app config from disk.
      final config = await AppConfig.load(configFile.path);

      // Then the project replaces inherited notifications with its own list.
      expect(
        config.projects['sample']!.issueAssistant.notifications,
        hasLength(1),
      );
      final notification =
          config.projects['sample']!.issueAssistant.notifications.single;
      expect(notification.webhookUrl, 'https://project.example.test/webhook');
      expect(notification.username, 'cws');

      // And notification event enums are parsed from snake_case values.
      expect(notification.events, {
        NotificationEvent.responderFailed,
        NotificationEvent.noReply,
      });
    });

    /// ```gherkin
    /// Scenario: Load camelCase config with shared worktree root
    ///   Given camelCase config with dataDir, worktreeDir, and project settings
    ///   When loading the app config from disk
    ///   Then the app exposes the configured data and worktree directories
    ///   And each project keeps the configured camelCase settings
    /// ```
    test('Load camelCase config with shared worktree root', () async {
      // Given camelCase config with dataDir, worktreeDir, and project settings.
      final tempDir = await Directory.systemTemp.createTemp('cws-camel-case-');
      final configFile = File(p.join(tempDir.path, 'agent-orchestrator.yaml'));
      await configFile.writeAsString('''
dataDir: ~/.agent-orchestrator
worktreeDir: ~/.worktrees
defaults:
  issueAssistant:
    enabled: false
projects:
  sample:
    repo: owner/sample
    path: ${tempDir.path}
    defaultBranch: trunk
    sessionPrefix: ao
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

      // And each project keeps the configured camelCase settings.
      expect(config.projects['sample'], isNotNull);
      expect(config.projects['sample']!.defaultBranch, 'trunk');
      expect(config.projects['sample']!.sessionPrefix, 'ao');
      expect(config.projects['sample']!.issueAssistant.enabled, isFalse);
    });

    /// ```gherkin
    /// Scenario: Reject snake_case config keys
    ///   Given a config that still uses snake_case keys
    ///   When loading the app config from disk
    ///   Then loading fails with a clear config error
    /// ```
    test('Reject snake_case config keys', () async {
      // Given a config that still uses snake_case keys.
      final tempDir = await Directory.systemTemp.createTemp(
        'cws-snake-case-invalid-',
      );
      final configFile = File(p.join(tempDir.path, 'agent-orchestrator.yaml'));
      await configFile.writeAsString('''
worktree_dir: ~/.worktrees
projects:
  sample:
    repo: owner/sample
    path: ${tempDir.path}
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
            contains('worktree_dir'),
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

    /// ```gherkin
    /// Scenario: Generate a starter config that parses as valid YAML
    ///   Given the built-in initial config renderer
    ///   When writing the generated starter config to disk
    ///   Then the file parses through the normal app config loader
    ///   And the required starter values stay available to users
    /// ```
    test('Generate a starter config that parses as valid YAML', () async {
      // Given the built-in initial config renderer.
      final tempDir = await Directory.systemTemp.createTemp('cws-init-config-');
      final configFile = File(p.join(tempDir.path, 'agent-orchestrator.yaml'));
      final contents = AppConfig.renderInitialConfig();

      // When writing the generated starter config to disk.
      await configFile.writeAsString(contents);
      final config = await AppConfig.load(configFile.path);

      // Then the file parses through the normal app config loader.
      expect(config.projects['sample'], isNotNull);

      // And the required starter values stay available to users.
      expect(
        config.dataDir,
        p.join(Platform.environment['HOME']!, '.agent-orchestrator'),
      );
      expect(
        config.worktreeDir,
        p.join(Platform.environment['HOME']!, '.worktrees'),
      );
      expect(config.projects['sample']!.repo, 'owner/repo');
      expect(
        config.projects['sample']!.path,
        p.join(Platform.environment['HOME']!, 'path/to/repo'),
      );
      expect(config.projects['sample']!.defaultBranch, 'main');
      expect(config.projects['sample']!.issueAssistant.mentionTriggers, [
        '@codex',
        '@helper',
      ]);
    });

    /// ```gherkin
    /// Scenario: Parse uncommented optional starter fields
    ///   Given a generated starter config with optional example lines uncommented
    ///   When loading that config through the normal parser
    ///   Then the uncommented optional values are accepted
    ///   And the parsed config reflects the example optional settings
    /// ```
    test('Parse uncommented optional starter fields', () async {
      // Given a generated starter config with optional example lines uncommented.
      final tempDir = await Directory.systemTemp.createTemp(
        'cws-init-optional-',
      );
      final configFile = File(p.join(tempDir.path, 'agent-orchestrator.yaml'));
      final contents = AppConfig.renderInitialConfig()
          .replaceFirst(
            '    # capabilities: ["planning", "bug_verification"]',
            '    capabilities: ["planning", "bug_verification"]',
          )
          .replaceFirst(
            '    # commentTag: code-work-spawner',
            '    commentTag: code-work-spawner',
          )
          .replaceFirst('    # responders:', '    responders:')
          .replaceFirst('    #   - id: codex', '      - id: codex')
          .replaceFirst('    #     command: codex', '        command: codex')
          .replaceFirst(
            '    #     args: ["exec", "--json"]',
            '        args: ["exec", "--json"]',
          )
          .replaceFirst('    #     timeout: 10m', '        timeout: 10m')
          .replaceFirst('    # issueAssistant:', '    issueAssistant:')
          .replaceFirst('    #   enabled: true', '      enabled: true')
          .replaceFirst(
            '    #   mentionTriggers: ["@helper"]',
            '      mentionTriggers: ["@helper"]',
          )
          .replaceFirst(
            '    # sessionPrefix: sample',
            '    sessionPrefix: sample',
          );
      await configFile.writeAsString(contents);

      // When loading that config through the normal parser.
      final config = await AppConfig.load(configFile.path);

      // Then the uncommented optional values are accepted.
      expect(config.projects['sample'], isNotNull);

      // And the parsed config reflects the example optional settings.
      expect(config.defaults.commentTag, 'code-work-spawner');
      expect(config.defaults.responders.single.id, 'codex');
      expect(
        config.defaults.capabilities,
        containsAll({
          AssistantCapability.planning,
          AssistantCapability.bugVerification,
        }),
      );
      expect(config.projects['sample']!.sessionPrefix, 'sample');
      expect(config.projects['sample']!.issueAssistant.mentionTriggers, [
        '@helper',
      ]);
    });
  });
}
