import 'dart:io';

import 'package:dotenv/dotenv.dart' as dotenv;
import 'package:path/path.dart' as p;

class AppEnvironment {
  static Map<String, String> _variables = Map.unmodifiable(
    Platform.environment,
  );

  static Map<String, String> get variables => _variables;

  static String? get(String key) => _variables[key];

  static void loadForConfig(String configPath) {
    final loader = dotenv.DotEnv(includePlatformEnvironment: true, quiet: true);
    loader.load([p.join(p.dirname(p.absolute(configPath)), '.env')]);
    // ignore: invalid_use_of_visible_for_testing_member
    _variables = Map.unmodifiable(loader.map);
  }

  static void resetForTest([Map<String, String>? variables]) {
    _variables = Map.unmodifiable(variables ?? Platform.environment);
  }
}
