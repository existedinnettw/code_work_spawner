import 'dart:convert';
import 'dart:io';

import 'script_utils.dart';

Future<void> writeGosmeeForwardScript({
  required File gosmeeScript,
  required String publicUrl,
  required Map<String, Object?> payload,
  File? gosmeeLog,
}) async {
  final buffer = StringBuffer()
    ..writeln('#!/usr/bin/env bash')
    ..writeln('set -euo pipefail');

  if (gosmeeLog != null) {
    buffer.writeln(
      r'''printf '%s\n' "$*" >> '''
      '"${bashScriptPath(gosmeeLog.path)}"',
    );
  }

  buffer
    ..writeln(
      r'''if [[ "$1" == "--output" && "$2" == "json" && "$3" == "client" && "$4" == "--new-url" ]]; then''',
    )
    ..writeln(
      r'''  printf '%s\n' '''
      "'$publicUrl'",
    )
    ..writeln('  exit 0')
    ..writeln('fi');

  buffer
    ..writeln(r'''if [[ "$1" == "client" ]]; then''')
    ..writeln(r'''  url="$2"''')
    ..writeln(r'''  target="$3"''')
    ..writeln(
      r'''  if [[ "$url" != '''
      "'$publicUrl'"
      r''' ]]; then''',
    )
    ..writeln(r'''    echo "unexpected gosmee url: $url" >&2''')
    ..writeln('    exit 1')
    ..writeln(r'''  fi''')
    ..writeln(r'''  curl -sS -X POST \''')
    ..writeln(r'''    -H "Content-Type: application/json" \''')
    ..writeln(r'''    -H "X-Gitea-Event: issue_comment" \''')
    ..writeln(r'''    --data-binary @- "$target" <<'JSON' >/dev/null''')
    ..writeln(jsonEncode(payload))
    ..writeln('JSON')
    ..writeln(r'''  while true; do''')
    ..writeln(r'''    sleep 60''')
    ..writeln(r'''  done''')
    ..writeln('fi');

  buffer
    ..writeln(r'''echo "unexpected gosmee args: $*" >&2''')
    ..writeln('exit 1');

  await gosmeeScript.writeAsString(buffer.toString());
  await makeScriptExecutable(gosmeeScript);
}
