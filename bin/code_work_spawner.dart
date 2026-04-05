import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:code_work_spawner/code_work_spawner.dart';
import 'package:logging/logging.dart';

Future<void> main(List<String> arguments) async {
  _configureLogging();

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
        'GitHub issue thread assistant with an Agent Orchestrator style YAML config.',
      ) {
    argParser
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
      );

    addCommand(_InitConfigCommand());
  }

  @override
  Future<void> runCommand(ArgResults topLevelResults) async {
    if (topLevelResults['help'] as bool) {
      stdout.writeln(usage);
      return;
    }

    if (topLevelResults.command != null) {
      await super.runCommand(topLevelResults);
      return;
    }

    final config = await AppConfig.load(topLevelResults['config'] as String);
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
      databasePath: topLevelResults['db'] as String,
      ghCommand: topLevelResults['gh-command'] as String,
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

void _configureLogging() {
  hierarchicalLoggingEnabled = true;
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    stdout.writeln(
      '[${record.loggerName}] ${record.level.name}: ${record.message}',
    );
  });
}
