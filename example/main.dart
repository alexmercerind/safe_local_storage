import 'dart:io';

import 'package:path/path.dart';
import 'package:safe_local_storage/safe_local_storage.dart';

const data = {'foo': 'bar'};

Future<void> main() async {
  final storage = SafeLocalStorage(location);
  await storage.write(data);
  print(await storage.read());
}

String get location {
  final script = Platform.script.toFilePath();
  final parent = File(script).parent.path;
  return join(parent, 'cache.json');
}
