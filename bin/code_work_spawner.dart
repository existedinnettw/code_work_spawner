import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:code_work_spawner/code_work_spawner.dart';

Future<void> main(List<String> arguments) async {
  final runner = _CodeWorkSpawnerCommandRunner();
  try {
    await runner.run(arguments);
  } on UsageException catch (error) {
    stdout.writeln(error);
    exitCode = 64;
  }
}

class _CodeWorkSpawnerCommandRunner extends CommandRunner<void> {
  _CodeWorkSpawnerCommandRunner()
    : super(
        'code_work_spawner',
        'Repository issue thread assistant with a YAML config.',
      ) {
    argParser
      ..addFlag(
        'once',
        abbr: '1',
        help: 'Run a single reconciliation cycle and exit.',
        negatable: false,
      )
      ..addOption(
        'config',
        abbr: 'c',
        help: 'Path to the YAML config file.',
        defaultsTo: 'CWS_conf.yaml',
      )
      ..addOption(
        'db',
        help: 'Path to the SQLite database file.',
        defaultsTo: '.code_work_spawner.sqlite3',
      )
      ..addOption(
        'gh-command',
        help: 'Path to the gh executable.',
        defaultsTo: 'gh',
      )
      ..addOption(
        'glab-command',
        help: 'Path to the glab executable.',
        defaultsTo: 'glab',
      )
      ..addOption(
        'tea-command',
        help: 'Path to the tea executable.',
        defaultsTo: 'tea',
      )
      ..addOption(
        'gosmee-command',
        help: 'Path to the gosmee executable.',
        defaultsTo: 'gosmee',
      )
      ..addOption(
        'log-level',
        help: 'Minimum log level: trace, debug, info, warn, error.',
      );

    addCommand(_InitConfigCommand());
  }

  @override
  Future<void> runCommand(ArgResults topLevelResults) async {
    final cliMinimumLevel = _resolveCliMinimumLevel(
      topLevelResults['log-level'] as String?,
    );
    _configureLogging(
      cliMinimumLevel: cliMinimumLevel,
      environment: AppEnvironment.variables,
    );

    if (topLevelResults['help'] as bool) {
      stdout.writeln(usage);
      return;
    }

    if (topLevelResults.command != null) {
      await super.runCommand(topLevelResults);
      return;
    }

    final configPath = topLevelResults['config'] as String;
    AppEnvironment.loadForConfig(configPath);
    _configureLogging(
      cliMinimumLevel: cliMinimumLevel,
      environment: AppEnvironment.variables,
    );

    final config = await AppConfig.load(configPath);
    final logger = AppLogger('code_work_spawner.cli');
    logger.debug(
      'startup once=${topLevelResults["once"]} '
      'config=${topLevelResults["config"]} '
      'db=${topLevelResults["db"]}',
    );
    logger.info(
      'loaded config=${config.configPath} '
      'projects=${config.projects.length} '
      'worktreeDir=${config.worktreeDir ?? "(system temp)"}',
    );
    for (final project in config.projects.values) {
      final repoDirectory = Directory(project.path);
      final eventSource = project.issueAssistant.eventSource;
      logger.info(
        'project=${project.key} '
        'repo=${project.repo} '
        'path=${project.path} '
        'exists=${await repoDirectory.exists()} '
        'enabled=${project.issueAssistant.enabled} '
        'tracker_provider=${project.provider.name} '
        'scm_provider=${project.scm.provider.name} '
        'event_source=${_eventSourceKindValue(eventSource.type)}'
        '${_cliEventSourceSettings(eventSource)}',
      );
    }
    final app = await IssueAssistantApp.open(
      config: config,
      databasePath: topLevelResults['db'] as String,
      ghCommand: topLevelResults['gh-command'] as String,
      glabCommand: topLevelResults['glab-command'] as String,
      gosmeeCommand: topLevelResults['gosmee-command'] as String,
      teaCommand: topLevelResults['tea-command'] as String,
    );

    try {
      if (topLevelResults['once'] as bool) {
        await app.runOnce();
        return;
      }
      await app.run();
    } finally {
      await app.close();
    }
  }

  AppLogLevel? _resolveCliMinimumLevel(String? value) {
    if (value == null) {
      return null;
    }
    final parsed = AppLogger.parseLevel(value);
    if (parsed == null || parsed == AppLogLevel.fatal) {
      throw UsageException(
        'Invalid value for --log-level "$value". '
        'Allowed values: trace, debug, info, warn, error.',
        usage,
      );
    }
    return parsed;
  }
}

String _cliEventSourceSettings(IssueEventSourceConfig eventSource) {
  return switch (eventSource) {
    PollingIssueEventSourceConfig(:final pollInterval) =>
      ' poll_interval=$pollInterval',
    ChannelIssueEventSourceConfig(
      :final reconciliation,
      :final reconcileInterval,
    ) =>
      ' reconciliation=${_reconciliationKindValue(reconciliation)} '
          'reconcile_interval=$reconcileInterval',
  };
}

String _eventSourceKindValue(IssueTrackerEventSourceKind value) {
  return switch (value) {
    IssueTrackerEventSourceKind.ghPolling => 'gh/polling',
    IssueTrackerEventSourceKind.glabPolling => 'glab/polling',
    IssueTrackerEventSourceKind.teaPolling => 'tea/polling',
    IssueTrackerEventSourceKind.opPolling => 'op/polling',
    IssueTrackerEventSourceKind.ghGosmee => 'gh/gosmee',
    IssueTrackerEventSourceKind.glabGosmee => 'glab/gosmee',
    IssueTrackerEventSourceKind.ghWebhookForward => 'gh/webhook-forward',
    IssueTrackerEventSourceKind.teaGosmee => 'tea/gosmee',
  };
}

String _reconciliationKindValue(IssueTrackerReconciliationKind value) {
  return switch (value) {
    IssueTrackerReconciliationKind.startupOnly => 'startup-only',
    IssueTrackerReconciliationKind.continuous => 'continuous',
  };
}

class _InitConfigCommand extends Command<void> {
  @override
  String get name => 'init-config';

  @override
  String get description => 'Print or write a starter config file.';

  @override
  String get invocation => 'code_work_spawner init-config [arguments]';

  _InitConfigCommand() {
    argParser
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Write the starter config to a file.',
      )
      ..addFlag(
        'force',
        abbr: 'f',
        help: 'Overwrite the output file if it already exists.',
        negatable: false,
      );
  }

  @override
  Future<void> run() async {
    final outputPath = argResults!['output'] as String?;
    final force = argResults!['force'] as bool;
    final content = AppConfig.renderInitialConfig();

    if (outputPath == null) {
      stdout.writeln(content);
      return;
    }

    final outputFile = File(outputPath);
    if (await outputFile.exists() && !force) {
      stderr.writeln(
        'Refusing to overwrite existing file: $outputPath. Use --force to replace it.',
      );
      exitCode = 2;
      return;
    }

    await outputFile.parent.create(recursive: true);
    await outputFile.writeAsString('$content\n');
    stdout.writeln('Wrote starter config to ${outputFile.path}');
  }
}

void _configureLogging({
  required Map<String, String> environment,
  AppLogLevel? cliMinimumLevel,
}) {
  AppLogger.configure(
    minimumLevel:
        cliMinimumLevel ??
        AppLogger.resolveMinimumLevel(environment, fallback: AppLogLevel.info),
    useColors: stdout.hasTerminal,
  );
}
