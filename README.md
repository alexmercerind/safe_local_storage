# [package:safe_local_storage](https://github.com/alexmercerind/safe_local_storage)

🗃️ A safe caching library to read/write values on local storage.

## Features

- **Atomic :** A `write` either succeeds completely or fails completely, cache is never left in corrupt state.
- **Safe to concurrency :** Multiple concurrent async `write` operations keep correct order & isolation is maintained.
- **Roll-back support :** In case of corruption, old state will be restored & saved values will remain safe. Safety to:
  - Closing application in the middle of on-going `write`.
  - Forcibly killing process.
  - Power failure.
- **Minimal :** 100% Dart, are no native calls. Just reads/writes your values in a very safe manner.
- **Customizable cache location :** You decide where your app's cache is kept, matching your project's model.
- **Isolate friendly :** Data is deserialized/serialized on another isolate during `read` or `write`.
- **Well tested :** [Learn more](https://github.com/harmonoid/safe_local_storage/blob/master/test/safe_local_storage_test.dart).
- **Correctly handles long file-paths on Windows :** [Learn more](https://github.com/dart-lang/sdk/issues/27825).

## Install

Add in your `pubspec.yaml`.

```yaml
dependencies:
  safe_local_storage: ^1.0.0
```

## Example

### Basics

A minimal example to get started.

```dart
/// Create a [SafeLocalStorage] object, decide where you want to keep your cache.
final storage = SafeLocalStorage('/path/to/your/cache/file.json');
/// Write your data, will be stored locally.
await storage.write(
  {
    'foo': 'bar',
  },
);
/// Perform read.
final data = await storage.read();
print(data);
/// {foo: bar}
```

### Fallback

Set the fallback value. This is returned by the `read` if:

- No existing cache is found.
- Cache was found in corrupt state & roll-back failed (never going to happen).

```dart
final storage = SafeLocalStorage(
  '/path/to/your/cache/file.json',
  /// Set the [fallback] value for this instance of cache storage.
  fallback: {
    'default_value': 0,
    'msg': 'No existing cache found.',
  },
);
print(await storage.read());
/// {default_value: 0, msg: No existing cache found.}
```

### Delete

Remove the cache file & clean-up the transaction records & history.

```dart
final storage = SafeLocalStorage(
  '/path/to/your/cache/file.json',
);
await storage.write(
  {
    'foo': 'bar',
  },
);
await storage.delete();
```

### Location

Giving raw control over the cache's location is a good thing for some.

Generally speaking, you can use this getter to get location for a new cache file in your app:

Still, it's not a good idea to store all the values in one single file.

```dart
import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

/// Create [SafeLocalStorage].
final storage = SafeLocalStorage(location);

/// A getter for default cache location, specific to your app.
String get location {
  switch (Platform.operatingSystem) {
    case 'windows':
      return join(
        Platform.environment['USERPROFILE']!,
        'AppData',
        'Roaming',
        'YOUR_APP_NAME',
        'cache.json',
      );
    case 'linux':
      return join(
        Platform.environment['HOME']!,
        '.config',
        'YOUR_APP_NAME',
        'cache.json',
      );
    case 'android':
      /// From `package:path_provider`.
      return getExternalStorageDirectory();
    default:
      throw Exception(
          'No implementation found for platform: ${Platform.operatingSystem}');
  }
}
```

## License

Copyright © 2022, Hitesh Kumar Saini <<saini123hitesh@gmail.com>>

This project & the work under this repository is governed by MIT license that can be found in the [LICENSE](https://github.com/harmonoid/safe_local_storage/blob/master/LICENSE) file.
