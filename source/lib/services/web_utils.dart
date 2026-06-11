import 'dart:async';
import 'web_utils_stub.dart'
    if (dart.library.html) 'web_utils_web.dart' as loader;

Future<void> performWebUpdateCheck() async {
  await loader.checkAndReloadWeb();
}
