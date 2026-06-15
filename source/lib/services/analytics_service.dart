import 'analytics_service_stub.dart'
    if (dart.library.html) 'analytics_service_web.dart' as impl;

class AnalyticsService {
  static void init() {
    impl.initAnalytics();
  }

  static void trackEvent(String name, {Map<String, dynamic>? parameters}) {
    impl.logEvent(name, parameters);
  }

  static void trackScreen(String screenName) {
    impl.logScreen(screenName);
  }
}
