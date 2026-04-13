import 'dart:io';

import 'package:code_work_spawner/code_work_spawner.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String _resolveTestHomeDirectory() {
  String? getEnv(String key) {
    final direct = Platform.environment[key];
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }
    for (final entry in Platform.environment.entries) {
      if (entry.key.toLowerCase() == key.toLowerCase() &&
          entry.value.isNotEmpty) {
        return entry.value;
      }
    }
    return null;
  }

  final home = getEnv('HOME');
  if (home != null) {
    return home;
  }

  final userProfile = getEnv('USERPROFILE');
  if (userProfile != null) {
    return userProfile;
  }

  final homeDrive = getEnv('HOMEDRIVE');
  final homePath = getEnv('HOMEPATH');
  if (homeDrive != null && homePath != null) {
    return '$homeDrive$homePath';
  }

  throw StateError('No home directory environment variables are set.');
}

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
      final configFile = File(p.join(tempDir.path, 'CWS_conf.yaml'));
      await configFile.writeAsString('''
defaults:
  issueAssistant:
    enabled: true
    maxResponsesAfterHuman: 2
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
      expect(config.projects['sample']!.provider, IssueTrackerProvider.github);
      expect(config.projects['sample']!.repoSlug!.owner, 'owner');
      expect(config.projects['sample']!.repoSlug!.name, 'sample');
      expect(config.projects['sample']!.issueAssistant.mentionTriggers, [
        '@helper',
      ]);
      expect(
        config.projects['sample']!.issueAssistant.maxResponsesAfterHuman,
        2,
      );
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
      final configFile = File(p.join(tempDir.path, 'CWS_conf.yaml'));
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
        (config.projects['sample']!.issueAssistant.eventSource
                as PollingIssueEventSourceConfig)
            .pollInterval,
        const Duration(seconds: 30),
      );
      expect(
        config.projects['sample']!.issueAssistant.eventSource,
        isA<PollingIssueEventSourceConfig>(),
      );
      expect(config.projects['sample']!.issueAssistant.maxConcurrentIssues, 3);
    });

    /// ```gherkin
    /// Scenario: Resolve config placeholders from a colocated dotenv file
    ///   Given an orchestrator config with environment placeholders and a colocated dotenv file
    ///   When loading the app config from disk
    ///   Then placeholder values are resolved from the dotenv file
    ///   And later runtime lookups use the same loaded environment values
    /// ```
    test('Resolve config placeholders from a colocated dotenv file', () async {
      // Given an orchestrator config with environment placeholders and a colocated dotenv file.
      final tempDir = await Directory.systemTemp.createTemp('cws-dotenv-');
      final configFile = File(p.join(tempDir.path, 'CWS_conf.yaml'));
      final dotenvFile = File(p.join(tempDir.path, '.env'));
      addTearDown(AppEnvironment.resetForTest);
      await dotenvFile.writeAsString('''
CWS_SAMPLE_WEBHOOK=https://dotenv.example.test/webhook
CWS_LOG_LEVEL=debug
''');
      await configFile.writeAsString('''
defaults:
  issueAssistant:
    notifications:
      - type: discordWebhook
        webhookUrl: \${CWS_SAMPLE_WEBHOOK}
projects:
  sample:
    repo: owner/sample
    path: ${tempDir.path}
''');

      // When loading the app config from disk.
      final config = await AppConfig.load(configFile.path);

      // Then placeholder values are resolved from the dotenv file.
      expect(
        config
            .projects['sample']!
            .issueAssistant
            .notifications
            .single
            .webhookUrl,
        'https://dotenv.example.test/webhook',
      );

      // And later runtime lookups use the same loaded environment values.
      expect(AppEnvironment.get('CWS_LOG_LEVEL'), 'debug');
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
      final configFile = File(p.join(tempDir.path, 'CWS_conf.yaml'));
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
      final configFile = File(p.join(tempDir.path, 'CWS_conf.yaml'));
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
    ///   And notification enums are parsed from their config values
    /// ```
    test('Merge notification defaults with project overrides', () async {
      // Given camelCase config with default notifications and a project-specific notification override.
      final tempDir = await Directory.systemTemp.createTemp(
        'cws-notification-config-',
      );
      final configFile = File(p.join(tempDir.path, 'CWS_conf.yaml'));
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

      // And notification enums are parsed from their config values.
      expect(notification.events, {
        NotificationEvent.responderFailed,
        NotificationEvent.noReply,
      });
      expect(notification.type, NotificationType.discordWebhook);
    });

    /// ```gherkin
    /// Scenario: Load a desktop notifier from config
    ///   Given camelCase config with a desktop notifier
    ///   When loading the app config from disk
    ///   Then the notifier type is parsed from the config value
    ///   And the configured events are available to the app
    /// ```
    test('Load a desktop notifier from config', () async {
      // Given camelCase config with a desktop notifier.
      final tempDir = await Directory.systemTemp.createTemp(
        'cws-desktop-notification-config-',
      );
      final configFile = File(p.join(tempDir.path, 'CWS_conf.yaml'));
      await configFile.writeAsString('''
defaults:
  issueAssistant:
    notifications:
      - type: desktop
        enabled: true
        events: ["mention_detected", "reply_posted"]
projects:
  sample:
    repo: owner/sample
    path: ${tempDir.path}
''');

      // When loading the app config from disk.
      final config = await AppConfig.load(configFile.path);

      // Then the notifier type is parsed from the config value.
      final notification =
          config.projects['sample']!.issueAssistant.notifications.single;
      expect(notification.type, NotificationType.desktop);

      // And the configured events are available to the app.
      expect(notification.events, {
        NotificationEvent.mentionDetected,
        NotificationEvent.replyPosted,
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
      final configFile = File(p.join(tempDir.path, 'CWS_conf.yaml'));
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
      final home = _resolveTestHomeDirectory();

      // Then the app exposes the configured data and worktree directories.
      expect(config.dataDir, p.join(home, '.agent-orchestrator'));
      expect(config.worktreeDir, p.join(home, '.worktrees'));

      // And each project keeps the configured camelCase settings.
      expect(config.projects['sample'], isNotNull);
      expect(config.projects['sample']!.defaultBranch, 'trunk');
      expect(config.projects['sample']!.sessionPrefix, 'ao');
      expect(config.projects['sample']!.scm.provider, ScmProvider.github);
      expect(config.projects['sample']!.issueAssistant.enabled, isFalse);
    });

    /// ```gherkin
    /// Scenario: Infer a Gitea issue tracker provider from the event source
    ///   Given a config whose project sets tea/polling as the event source type
    ///   When loading the app config from disk
    ///   Then the project infers the Gitea provider
    ///   And the repository slug still parses normally
    /// ```
    test('Infer a Gitea issue tracker provider from the event source', () async {
      // Given a config whose project sets tea/polling as the event source type.
      final tempDir = await Directory.systemTemp.createTemp('cws-gitea-');
      final configFile = File(p.join(tempDir.path, 'CWS_conf.yaml'));
      await configFile.writeAsString('''
projects:
  sample:
    issueTracker:
      eventSource:
        type: tea/polling
    repo: owner/sample
    path: ${tempDir.path}
''');

      // When loading the app config from disk.
      final config = await AppConfig.load(configFile.path);

      // Then the project infers the Gitea provider.
      expect(config.projects['sample']!.provider, IssueTrackerProvider.gitea);
      expect(config.projects['sample']!.scm.provider, ScmProvider.gitea);

      // And the repository slug still parses normally.
      expect(config.projects['sample']!.repoSlug!.fullName, 'owner/sample');
      expect(
        config.projects['sample']!.issueAssistant.eventSource.type,
        IssueTrackerEventSourceKind.teaPolling,
      );
    });

    /// ```gherkin
    /// Scenario: Infer a GitLab issue tracker provider from the event source
    ///   Given a config whose project sets glab/polling as the event source type
    ///   When loading the app config from disk
    ///   Then the project infers the GitLab provider
    ///   And the project uses GitLab polling and GitLab SCM by default
    /// ```
    test('Infer a GitLab issue tracker provider from the event source', () async {
      // Given a config whose project sets glab/polling as the event source type.
      final tempDir = await Directory.systemTemp.createTemp('cws-gitlab-');
      final configFile = File(p.join(tempDir.path, 'CWS_conf.yaml'));
      await configFile.writeAsString('''
projects:
  sample:
    issueTracker:
      eventSource:
        type: glab/polling
    repo: group/subgroup/sample
    path: ${tempDir.path}
''');

      // When loading the app config from disk.
      final config = await AppConfig.load(configFile.path);

      // Then the project infers the GitLab provider.
      expect(config.projects['sample']!.provider, IssueTrackerProvider.gitlab);

      // And the project uses GitLab polling and GitLab SCM by default.
      expect(config.projects['sample']!.scm.provider, ScmProvider.gitlab);
      expect(
        config.projects['sample']!.issueAssistant.eventSource.type,
        IssueTrackerEventSourceKind.glabPolling,
      );
      expect(config.projects['sample']!.repo, 'group/subgroup/sample');
    });

    /// ```gherkin
    /// Scenario: Infer an OpenProject issue tracker provider from the event source
    ///   Given a config whose project sets op/polling as the event source type
    ///   And the project declares an explicit SCM provider
    ///   When loading the app config from disk
    ///   Then the project infers the OpenProject provider
    ///   And the project uses op/polling as its default issue event source
    /// ```
    test(
      'Infer an OpenProject issue tracker provider from the event source',
      () async {
        // Given a config whose project sets op/polling as the event source type.
        final tempDir = await Directory.systemTemp.createTemp(
          'cws-openproject-',
        );
        final configFile = File(p.join(tempDir.path, 'CWS_conf.yaml'));
        await configFile.writeAsString('''
projects:
  sample:
    issueTracker:
      eventSource:
        type: op/polling
    scm:
      provider: github
    repo: 42
    path: ${tempDir.path}
''');

        // When loading the app config from disk.
        final config = await AppConfig.load(configFile.path);

        // Then the project infers the OpenProject provider.
        expect(
          config.projects['sample']!.provider,
          IssueTrackerProvider.openproject,
        );
        expect(config.projects['sample']!.scm.provider, ScmProvider.github);

        // And the project uses op/polling as its default issue event source.
        expect(
          config.projects['sample']!.issueAssistant.eventSource.type,
          IssueTrackerEventSourceKind.opPolling,
        );
      },
    );

    /// ```gherkin
    /// Scenario: Require an explicit SCM provider for OpenProject projects
    ///   Given a config whose project uses op/polling as the event source
    ///   And the project omits scm.provider
    ///   When loading the app config from disk
    ///   Then loading fails with a clear SCM requirement error
    /// ```
    test('Require an explicit SCM provider for OpenProject projects', () async {
      // Given a config whose project uses op/polling as the event source.
      final tempDir = await Directory.systemTemp.createTemp(
        'cws-openproject-missing-scm-',
      );
      final configFile = File(p.join(tempDir.path, 'CWS_conf.yaml'));
      await configFile.writeAsString('''
projects:
  sample:
    issueTracker:
      eventSource:
        type: op/polling
    repo: 42
    path: ${tempDir.path}
''');

      // And the project omits scm.provider.

      // When loading the app config from disk.
      final load = AppConfig.load(configFile.path);

      // Then loading fails with a clear SCM requirement error.
      await expectLater(
        load,
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains(
              'projects.sample.scm.provider is required for issue tracking provider: openproject',
            ),
          ),
        ),
      );
    });

    /// ```gherkin
    /// Scenario: Accept an OpenProject project name reference
    ///   Given a config whose project uses op/polling as the event source
    ///   And the project repo field is a human-readable project name
    ///   When loading the app config from disk
    ///   Then loading succeeds without requiring a numeric project id
    /// ```
    test('Accept an OpenProject project name reference', () async {
      // Given a config whose project uses op/polling as the event source.
      final tempDir = await Directory.systemTemp.createTemp(
        'cws-openproject-project-name-',
      );
      final configFile = File(p.join(tempDir.path, 'CWS_conf.yaml'));
      await configFile.writeAsString('''
projects:
  sample:
    issueTracker:
      eventSource:
        type: op/polling
    scm:
      provider: github
    repo: Demo project
    path: ${tempDir.path}
''');

      // And the project repo field is a human-readable project name.

      // When loading the app config from disk.
      final config = await AppConfig.load(configFile.path);

      // Then loading succeeds without requiring a numeric project id.
      expect(
        config.projects['sample']!.provider,
        IssueTrackerProvider.openproject,
      );
      expect(config.projects['sample']!.repo, 'Demo project');
    });

    /// ```gherkin
    /// Scenario: Load gh/gosmee as the issue event source
    ///   Given a GitHub project config that opts into gh/gosmee
    ///   When loading the app config from disk
    ///   Then the project keeps gh/gosmee as its event source
    ///   And the GitHub provider remains valid for that project
    /// ```
    test('Load gh/gosmee as the issue event source', () async {
      // Given a GitHub project config that opts into gh/gosmee.
      final tempDir = await Directory.systemTemp.createTemp('cws-gh-gosmee-');
      final configFile = File(p.join(tempDir.path, 'CWS_conf.yaml'));
      await configFile.writeAsString('''
projects:
  sample:
    issueTracker:
      eventSource:
        type: gh/gosmee
    repo: owner/sample
    path: ${tempDir.path}
''');

      // When loading the app config from disk.
      final config = await AppConfig.load(configFile.path);

      // Then the project keeps gh/gosmee as its event source.
      expect(
        config.projects['sample']!.issueAssistant.eventSource.type,
        IssueTrackerEventSourceKind.ghGosmee,
      );

      // And the GitHub provider remains valid for that project.
      expect(config.projects['sample']!.provider, IssueTrackerProvider.github);
    });

    /// ```gherkin
    /// Scenario: Load glab/gosmee as the issue event source
    ///   Given a GitLab project config that opts into glab/gosmee
    ///   When loading the app config from disk
    ///   Then the project keeps glab/gosmee as its event source
    ///   And the GitLab provider remains valid for that project
    /// ```
    test('Load glab/gosmee as the issue event source', () async {
      // Given a GitLab project config that opts into glab/gosmee.
      final tempDir = await Directory.systemTemp.createTemp('cws-glab-gosmee-');
      final configFile = File(p.join(tempDir.path, 'CWS_conf.yaml'));
      await configFile.writeAsString('''
projects:
  sample:
    issueTracker:
      eventSource:
        type: glab/gosmee
    repo: group/subgroup/sample
    path: ${tempDir.path}
''');

      // When loading the app config from disk.
      final config = await AppConfig.load(configFile.path);

      // Then the project keeps glab/gosmee as its event source.
      expect(
        config.projects['sample']!.issueAssistant.eventSource.type,
        IssueTrackerEventSourceKind.glabGosmee,
      );

      // And the GitLab provider remains valid for that project.
      expect(config.projects['sample']!.provider, IssueTrackerProvider.gitlab);
    });

    /// ```gherkin
    /// Scenario: Load an explicit SCM provider separately from the issue tracker
    ///   Given a config whose project uses a Gitea issue tracker and GitHub SCM
    ///   When loading the app config from disk
    ///   Then the project keeps the configured tracker provider
    ///   And the project also keeps the explicit SCM provider override
    /// ```
    test(
      'Load an explicit SCM provider separately from the issue tracker',
      () async {
        // Given a config whose project uses a Gitea issue tracker and GitHub SCM.
        final tempDir = await Directory.systemTemp.createTemp(
          'cws-explicit-scm-',
        );
        final configFile = File(p.join(tempDir.path, 'CWS_conf.yaml'));
        await configFile.writeAsString('''
projects:
  sample:
    issueTracker:
      eventSource:
        type: tea/polling
    scm:
      provider: github
    repo: owner/sample
    path: ${tempDir.path}
''');

        // When loading the app config from disk.
        final config = await AppConfig.load(configFile.path);

        // Then the project keeps the configured tracker provider.
        expect(config.projects['sample']!.provider, IssueTrackerProvider.gitea);

        // And the project also keeps the explicit SCM provider override.
        expect(config.projects['sample']!.scm.provider, ScmProvider.github);
      },
    );

    /// ```gherkin
    /// Scenario: Keep the legacy issue tracker provider as a fallback
    ///   Given a config whose project still sets issueTracker.provider to gitea
    ///   And the project omits issueTracker.eventSource.type
    ///   When loading the app config from disk
    ///   Then the project keeps the configured Gitea provider
    ///   And the polling event source is rewritten to tea/polling
    /// ```
    test('Keep the legacy issue tracker provider as a fallback', () async {
      // Given a config whose project still sets issueTracker.provider to gitea.
      final tempDir = await Directory.systemTemp.createTemp(
        'cws-legacy-provider-fallback-',
      );
      final configFile = File(p.join(tempDir.path, 'CWS_conf.yaml'));
      await configFile.writeAsString('''
projects:
  sample:
    issueTracker:
      provider: gitea
    repo: owner/sample
    path: ${tempDir.path}
''');

      // And the project omits issueTracker.eventSource.type.

      // When loading the app config from disk.
      final config = await AppConfig.load(configFile.path);

      // Then the project keeps the configured Gitea provider.
      expect(config.projects['sample']!.provider, IssueTrackerProvider.gitea);

      // And the polling event source is rewritten to tea/polling.
      expect(
        config.projects['sample']!.issueAssistant.eventSource.type,
        IssueTrackerEventSourceKind.teaPolling,
      );
    });

    /// ```gherkin
    /// Scenario: Reject conflicting legacy tracker and event source settings
    ///   Given a project config whose legacy tracker provider is gitea
    ///   And the project opts into gh/gosmee
    ///   When loading the app config from disk
    ///   Then loading fails with a clear conflict error
    /// ```
    test('Reject conflicting legacy tracker and event source settings', () async {
      // Given a project config whose legacy tracker provider is gitea.
      final tempDir = await Directory.systemTemp.createTemp(
        'cws-gh-gosmee-gitea-',
      );
      final configFile = File(p.join(tempDir.path, 'CWS_conf.yaml'));
      await configFile.writeAsString('''
projects:
  sample:
    issueTracker:
      provider: gitea
      eventSource:
        type: gh/gosmee
    repo: owner/sample
    path: ${tempDir.path}
''');

      // When loading the app config from disk.
      final load = AppConfig.load(configFile.path);

      // Then loading fails with a clear conflict error.
      await expectLater(
        load,
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains(
              'gh/gosmee implies issue tracker provider github, but the legacy configured provider is gitea',
            ),
          ),
        ),
      );
    });

    /// ```gherkin
    /// Scenario: Reject a legacy GitHub provider that conflicts with glab/gosmee
    ///   Given a project config whose legacy tracker provider is github
    ///   And the project opts into glab/gosmee
    ///   When loading the app config from disk
    ///   Then loading fails with a clear conflict error
    /// ```
    test(
      'Reject a legacy GitHub provider that conflicts with glab/gosmee',
      () async {
        // Given a project config whose legacy tracker provider is github.
        final tempDir = await Directory.systemTemp.createTemp(
          'cws-glab-gosmee-github-',
        );
        final configFile = File(p.join(tempDir.path, 'CWS_conf.yaml'));
        await configFile.writeAsString('''
projects:
  sample:
    issueTracker:
      provider: github
      eventSource:
        type: glab/gosmee
    repo: group/subgroup/sample
    path: ${tempDir.path}
''');

        // And the project opts into glab/gosmee.

        // When loading the app config from disk.
        final load = AppConfig.load(configFile.path);

        // Then loading fails with a clear conflict error.
        await expectLater(
          load,
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains(
                'glab/gosmee implies issue tracker provider gitlab, but the legacy configured provider is github',
              ),
            ),
          ),
        );
      },
    );

    /// ```gherkin
    /// Scenario: Load gh/webhook-forward as the issue event source
    ///   Given a GitHub project config that opts into gh/webhook-forward
    ///   When loading the app config from disk
    ///   Then the project keeps gh/webhook-forward as its event source
    ///   And the GitHub provider remains valid for that project
    /// ```
    test('Load gh/webhook-forward as the issue event source', () async {
      // Given a GitHub project config that opts into gh/webhook-forward.
      final tempDir = await Directory.systemTemp.createTemp(
        'cws-webhook-forward-',
      );
      final configFile = File(p.join(tempDir.path, 'CWS_conf.yaml'));
      await configFile.writeAsString('''
projects:
  sample:
    issueTracker:
      eventSource:
        type: gh/webhook-forward
    repo: owner/sample
    path: ${tempDir.path}
''');

      // When loading the app config from disk.
      final config = await AppConfig.load(configFile.path);

      // Then the project keeps gh/webhook-forward as its event source.
      expect(
        config.projects['sample']!.issueAssistant.eventSource.type,
        IssueTrackerEventSourceKind.ghWebhookForward,
      );

      // And the GitHub provider remains valid for that project.
      expect(config.projects['sample']!.provider, IssueTrackerProvider.github);
    });

    /// ```gherkin
    /// Scenario: Load channel reconciliation settings
    ///   Given a GitHub project config that uses gh/webhook-forward reconciliation settings
    ///   When loading the app config from disk
    ///   Then the project keeps the configured reconciliation mode
    ///   And the configured reconcile interval is parsed for channel recovery
    /// ```
    test('Load channel reconciliation settings', () async {
      // Given a GitHub project config that uses gh/webhook-forward reconciliation settings.
      final tempDir = await Directory.systemTemp.createTemp(
        'cws-channel-reconcile-',
      );
      final configFile = File(p.join(tempDir.path, 'CWS_conf.yaml'));
      await configFile.writeAsString('''
projects:
  sample:
    issueTracker:
      eventSource:
        type: gh/webhook-forward
        reconciliation: startup-only
        reconcileInterval: 5m
    repo: owner/sample
    path: ${tempDir.path}
''');

      // When loading the app config from disk.
      final config = await AppConfig.load(configFile.path);

      // Then the project keeps the configured reconciliation mode.
      expect(
        (config.projects['sample']!.issueAssistant.eventSource
                as ChannelIssueEventSourceConfig)
            .reconciliation,
        IssueTrackerReconciliationKind.startupOnly,
      );

      // And the configured reconcile interval is parsed for channel recovery.
      expect(
        (config.projects['sample']!.issueAssistant.eventSource
                as ChannelIssueEventSourceConfig)
            .reconcileInterval,
        const Duration(minutes: 5),
      );
    });

    /// ```gherkin
    /// Scenario: Reuse pollInterval as the fallback reconcile interval
    ///   Given a legacy channel-based project config that still sets pollInterval
    ///   When loading the app config from disk
    ///   Then the project keeps the parsed poll interval for backward compatibility
    ///   And the same value is reused as the reconcile interval
    /// ```
    test('Reuse pollInterval as the fallback reconcile interval', () async {
      // Given a legacy channel-based project config that still sets pollInterval.
      final tempDir = await Directory.systemTemp.createTemp(
        'cws-legacy-channel-poll-',
      );
      final configFile = File(p.join(tempDir.path, 'CWS_conf.yaml'));
      await configFile.writeAsString('''
projects:
  sample:
    issueTracker:
      eventSource:
        type: gh/webhook-forward
        pollInterval: 45s
    repo: owner/sample
    path: ${tempDir.path}
''');

      // When loading the app config from disk.
      final config = await AppConfig.load(configFile.path);

      // Then the project keeps the parsed poll interval for backward compatibility.
      expect(
        config.projects['sample']!.issueAssistant.eventSource,
        isA<ChannelIssueEventSourceConfig>(),
      );

      // And the same value is reused as the reconcile interval.
      expect(
        (config.projects['sample']!.issueAssistant.eventSource
                as ChannelIssueEventSourceConfig)
            .reconcileInterval,
        const Duration(seconds: 45),
      );
    });

    /// ```gherkin
    /// Scenario: Reject a legacy Gitea provider that conflicts with gh/webhook-forward
    ///   Given a project config whose legacy tracker provider is gitea
    ///   And the project opts into gh/webhook-forward
    ///   When loading the app config from disk
    ///   Then loading fails with a clear conflict error
    /// ```
    test(
      'Reject a legacy Gitea provider that conflicts with gh/webhook-forward',
      () async {
        // Given a project config whose legacy tracker provider is gitea.
        final tempDir = await Directory.systemTemp.createTemp(
          'cws-webhook-forward-gitea-',
        );
        final configFile = File(p.join(tempDir.path, 'CWS_conf.yaml'));
        await configFile.writeAsString('''
projects:
  sample:
    issueTracker:
      provider: gitea
      eventSource:
        type: gh/webhook-forward
    repo: owner/sample
    path: ${tempDir.path}
''');

        // When loading the app config from disk.
        final load = AppConfig.load(configFile.path);

        // Then loading fails with a clear conflict error.
        await expectLater(
          load,
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains(
                'gh/webhook-forward implies issue tracker provider github, but the legacy configured provider is gitea',
              ),
            ),
          ),
        );
      },
    );

    /// ```gherkin
    /// Scenario: Load tea/gosmee as the issue event source
    ///   Given a Gitea project config that opts into tea/gosmee
    ///   When loading the app config from disk
    ///   Then the project keeps tea/gosmee as its event source
    ///   And the Gitea provider remains valid for that project
    /// ```
    test('Load tea/gosmee as the issue event source', () async {
      // Given a Gitea project config that opts into tea/gosmee.
      final tempDir = await Directory.systemTemp.createTemp('cws-gosmee-');
      final configFile = File(p.join(tempDir.path, 'CWS_conf.yaml'));
      await configFile.writeAsString('''
projects:
  sample:
    issueTracker:
      eventSource:
        type: tea/gosmee
    repo: owner/sample
    path: ${tempDir.path}
''');

      // When loading the app config from disk.
      final config = await AppConfig.load(configFile.path);

      // Then the project keeps tea/gosmee as its event source.
      expect(
        config.projects['sample']!.issueAssistant.eventSource.type,
        IssueTrackerEventSourceKind.teaGosmee,
      );

      // And the Gitea provider remains valid for that project.
      expect(config.projects['sample']!.provider, IssueTrackerProvider.gitea);
    });

    /// ```gherkin
    /// Scenario: Reject a legacy GitHub provider that conflicts with tea/gosmee
    ///   Given a project config whose legacy tracker provider is github
    ///   And the project opts into tea/gosmee
    ///   When loading the app config from disk
    ///   Then loading fails with a clear conflict error
    /// ```
    test(
      'Reject a legacy GitHub provider that conflicts with tea/gosmee',
      () async {
        // Given a project config whose legacy tracker provider is github.
        final tempDir = await Directory.systemTemp.createTemp(
          'cws-gosmee-github-',
        );
        final configFile = File(p.join(tempDir.path, 'CWS_conf.yaml'));
        await configFile.writeAsString('''
projects:
  sample:
    issueTracker:
      provider: github
      eventSource:
        type: tea/gosmee
    repo: owner/sample
    path: ${tempDir.path}
''');

        // When loading the app config from disk.
        final load = AppConfig.load(configFile.path);

        // Then loading fails with a clear conflict error.
        await expectLater(
          load,
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains(
                'tea/gosmee implies issue tracker provider gitea, but the legacy configured provider is github',
              ),
            ),
          ),
        );
      },
    );

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
      final configFile = File(p.join(tempDir.path, 'CWS_conf.yaml'));
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
      final configFile = File(p.join(tempDir.path, 'CWS_conf.yaml'));
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
      final configFile = File(p.join(tempDir.path, 'CWS_conf.yaml'));
      final contents = AppConfig.renderInitialConfig();

      // When writing the generated starter config to disk.
      await configFile.writeAsString(contents);
      final config = await AppConfig.load(configFile.path);
      final home = _resolveTestHomeDirectory();

      // Then the file parses through the normal app config loader.
      expect(config.projects['sample'], isNotNull);

      // And the required starter values stay available to users.
      expect(config.dataDir, p.join(home, '.agent-orchestrator'));
      expect(config.projects['sample']!.provider, IssueTrackerProvider.github);
      expect(config.worktreeDir, p.join(home, '.worktrees'));
      expect(config.projects['sample']!.repo, 'owner/repo');
      expect(
        config.projects['sample']!.path,
        p.join(home, 'path', 'to', 'repo'),
      );
      expect(config.projects['sample']!.defaultBranch, 'main');
      expect(config.projects['sample']!.issueAssistant.mentionTriggers, [
        '@codex',
        '@helper',
      ]);
      expect(config.defaults.maxResponsesAfterHuman, 1);
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
      final configFile = File(p.join(tempDir.path, 'CWS_conf.yaml'));
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
      expect(
        config.projects['sample']!.issueAssistant.eventSource,
        isA<PollingIssueEventSourceConfig>(),
      );
      expect(config.defaults.maxResponsesAfterHuman, 1);
    });

    /// ```gherkin
    /// Scenario: Parse repository example configs
    ///   Given the checked-in example config files
    ///   When loading each example through the normal config parser
    ///   Then each example parses successfully
    ///   And the mention loop guard default is available in the loaded config
    /// ```
    test('Parse repository example configs', () async {
      // Given the checked-in example config files.
      final repoRoot = Directory.current.path;
      final examplePaths = [
        p.join(repoRoot, 'examples', 'simple-github.yaml'),
        p.join(repoRoot, 'examples', 'simple-gitlab.yaml'),
        p.join(repoRoot, 'examples', 'simple-gitea.yaml'),
      ];

      // When loading each example through the normal config parser.
      final configs = await Future.wait(examplePaths.map(AppConfig.load));

      // Then each example parses successfully.
      expect(configs, hasLength(3));

      // And the mention loop guard default is available in the loaded config.
      for (final config in configs) {
        expect(config.projects, isNotEmpty);
        expect(config.defaults.maxResponsesAfterHuman, 1);
      }
    });
  });
}
