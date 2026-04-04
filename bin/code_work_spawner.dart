import 'dart:io';

import 'package:args/args.dart';
import 'package:code_work_spawner/code_work_spawner.dart';
import 'package:logging/logging.dart';

Future<void> main(List<String> arguments) async {
  _configureLogging();

  final parser = ArgParser()
    ..addFlag(
      'once',
      abbr: '1',
      help: 'Run a single poll cycle and exit.',
      negatable: false,
    )
    ..addOption(
      'config',
      abbr: 'c',
      help: 'Path to agent-orchestrator.yaml.',
      defaultsTo: 'agent-orchestrator.yaml',
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
    ..addFlag('help', abbr: 'h', negatable: false);

  final results = parser.parse(arguments);
  if (results['help'] as bool) {
    stdout.writeln(parser.usage);
    return;
  }

  final config = await AppConfig.load(results['config'] as String);
  final logger = Logger('code_work_spawner.cli');
  logger.info(
    'loaded config=${config.configPath} '
    'projects=${config.projects.length} '
    'worktreeDir=${config.worktreeDir ?? "(system temp)"}',
  );
  for (final project in config.projects.values) {
    final repoDirectory = Directory(project.path);
    logger.info(
      'project=${project.key} '
      'repo=${project.repo} '
      'path=${project.path} '
      'exists=${await repoDirectory.exists()} '
      'enabled=${project.issueAssistant.enabled}',
    );
  }
  final app = await IssueAssistantApp.open(
    config: config,
    databasePath: results['db'] as String,
    ghCommand: results['gh-command'] as String,
  );

  try {
    if (results['once'] as bool) {
      await app.runOnce();
      return;
    }

    await app.run();
  } finally {
    await app.close();
  }
}

void _configureLogging() {
  hierarchicalLoggingEnabled = true;
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    stdout.writeln(
      '[${record.loggerName}] ${record.level.name}: ${record.message}',
    );
  });
}
