import 'dart:io';

import 'package:path/path.dart';
import 'package:safe_local_storage/safe_local_storage.dart';

Future<void> main() async {
  // Create a [SafeLocalStorage] object, decide where you want to keep your cache.
  final storage = SafeLocalStorage(location);
  // Write your data, will be stored locally.
  await storage.write(
    {
      'foo': 'bar',
    },
  );
  // Perform read.
  final data = await storage.read();
  print(data);
  // {foo: bar}
}

String get location {
  final script = Platform.script.toFilePath();
  final parent = File(script).parent.path;
  return join(
    parent,
    'cache.json',
  );
}
