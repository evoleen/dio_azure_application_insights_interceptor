A Dio interceptor that sends request metrics to Azure Application Insights.

This package is inspired by [a previous implementation for Firebase](https://github.com/darkxanter/firebase_performance_dio).

## Usage

```dart
final dio = Dio();
final insightsInterceptor = DioAzureApplicationInsightsInterceptor();
dio.interceptors.add(insightsInterceptor);
```

## Additional information

The interceptor will auto-configure itself if deployed on Azure and a connection to Application Insights is setup. Auto-configuration happens by reading the environment variable `APPLICATIONINSIGHTS_CONNECTION_STRING`.

Alternatively either a connection or an existing instance of `TelemetryClient` can be supplied.

If no parameters are supplied and the environment variable doesn't exist, the observer will not submit any logs (but also not produce any errors).

**Note**: The interceptor optionally supports injecting a custom HTTP client to submit telemetry data. Do *not* use the observed Dio instance as HTTP client for telemetry, because this would cause every telemetry item to again generate additional telemetry and thus spamming the logs.
