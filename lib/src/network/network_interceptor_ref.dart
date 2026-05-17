/// Abstract interface that [InkPalNetworkInterceptor] registers itself against.
///
/// VM extensions in [InkPalVmExtensions] delegate network control calls to
/// [instance]. If the app hasn't called [InkPalNetworkInterceptor.install()],
/// [instance] is null and the extensions return a helpful error message.
abstract class InkPalNetworkInterceptorRef {
  /// The active interceptor, or null if not installed.
  static InkPalNetworkInterceptorRef? instance;

  void addMockRule({
    required String urlPattern,
    required int responseCode,
    String? responseBody,
    required String method,
    required int delayMs,
  });

  void clearRules();
  void setOffline(bool offline);
  void setConditions(int delayMs, int lossPercent);
}
