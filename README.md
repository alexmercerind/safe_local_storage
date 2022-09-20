# [safe_local_storage](https://github.com/alexmercerind/safe_local_storage)

**🗃️ A safe caching library to read/write data on local storage.**

## Features

- **Atomic :** A `write` operation either succeeds completely or fails completely, cache is never left in corrupt state.
- **Safe to concurrency :** Even if multiple async operations call `write` concurrently, correct order & isolation is maintained. 
- **Roll-back support :** If cache is found corrupt, old state will be restored & data will remain safe. e.g. Safety to:
  - User closing app in the middle of on-going `write`.
  - Killing your app's process using [Task Manager](https://en.wikipedia.org/wiki/Task_Manager_(Windows)), [`htop`](https://htop.dev/) etc.
  - Power failure.
- **Minimal :** It's written in 100% Dart, there are no native calls. Just reads/writes your JSON data in a very safe manner.
- **Customizable cache location :** You decide where your app's cache is kept, matching your project's model.
- **Isolate friendly :** Data is deserialized/serialized on another isolate during `read` or `write`.
- **Well tested :** [Learn more](https://github.com/harmonoid/safe_local_storage/blob/master/test/safe_session_storage_test.dart).
- **Correctly handles long file-paths on Windows :** [Learn more](https://github.com/dart-lang/sdk/issues/27825).

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

### Location

Giving raw control over the cache's location is a good thing for some. 

Generally speaking, you can use this getter to get location for a new cache file in your app:

Still, it's not a good idea to store all the data in one single file.

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

## Why

First of all, this is built with requirements of [Harmonoid](https://github.com/harmonoid/harmonoid) in mind.

I'm aware there are _good_ solutions available like [`package:shared_preferences`](https://pub.dev/packages/shared_preferences) or [`package:isar`](https://pub.dev/packages/isar) & many more.

It's quite hard to believe but [`package:shared_preferences`](https://pub.dev/packages/shared_preferences) on Windows & Linux, just [treats your cache like any normal text file](https://github.com/flutter/plugins/blob/main/packages/shared_preferences/shared_preferences_windows/lib/shared_preferences_windows.dart). This makes your app's cache very-very prone to get corrupted. Your saved data will eventually get corrupted (with higher chances if you store large amount data) & there will be no way to bring it back. Secondly, it just keeps all the data in one single file, making the matters even worse. There's no atomicity, isolation or roll-back support. It's a really bad choice when building something useful, atleast on Windows or Linux.

The [`package:isar`](https://pub.dev/packages/isar) is quite good & seems well built, but I don't need Rust (or additional shared libraries) for something as simple as storing non-relational data. Dart is a natively compiled language & quite fast for the purpose.

There are other packages which can be used to store data on local storage, but they don't provide other things I want:

- I need control over the location where my app stores it's data or cache.
  Android offers safe [`SharedPreferences`](https://developer.android.com/reference/android/content/SharedPreferences), there's no concept of file location etc. & fine. It's used by used by [`package:shared_preferences`](https://pub.dev/packages/shared_preferences) internally, but Windows & Linux implementation is just unusable.
- I want my app's cache to never get corrupt.
  - [Harmonoid](https://github.com/harmonoid/harmonoid) caches user's huge large music library & other important configuration/settings.
  - Cache needs to remain on disk persistently after first-time indexing.
  - It needs to be updated after any new music files are added/deleted (which is quite often).
  - Ensuring that the cache remains in readable state is quite important. 
- I don't want query support etc. In my source-code, most operations are performed in-memory. Just read/write data & do it safely.
- I want to be as less platform-specific as possible.

## License

Copyright © 2022, Hitesh Kumar Saini <<saini123hitesh@gmail.com>>

This project & the work under this repository is governed by MIT license that can be found in the [LICENSE](https://github.com/harmonoid/safe_local_storage/blob/master/LICENSE) file.
