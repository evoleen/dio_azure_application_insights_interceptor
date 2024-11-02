import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:azure_application_insights/azure_application_insights.dart';
import 'package:dio/dio.dart';

/// [Dio] client interceptor that hooks into request/response process
/// and calls Azure Application Insights in between.
///
/// Additionally there is no good API of obtaining content length from interceptor
/// API so we're "approximating" the byte length based on headers & request data.
/// If you're not fine with this, you can provide your own implementation in the constructor
///
/// This interceptor might be counting parsing time into elapsed API call duration.
///
/// The interceptor will auto-configure if the APPLICATIONINSIGHTS_CONNECTION_STRING
/// environment variable exists. Otherwise inject the connection string or a
/// configured telemetry client. Be aware to NOT use the observed Dio instance
/// as HTTP client to submit telemetry, as otherwise submitting telemetry will
/// again cause telemetry to be logged.
class DioAzureApplicationInsightsInterceptor extends Interceptor {
  DioAzureApplicationInsightsInterceptor({
    this.requestContentLengthMethod = defaultRequestContentLength,
    this.responseContentLengthMethod = defaultResponseContentLength,
    String? connectionString,
    TelemetryClient? telemetryClient,
    http.Client? httpClient,
  }) {
    connectionString ??=
        Platform.environment['APPLICATIONINSIGHTS_CONNECTION_STRING'];

    if (telemetryClient != null) {
      _telemetryClient = telemetryClient;
    } else if (connectionString != null) {
      _telemetryClient = TelemetryClient(
        processor: BufferedProcessor(
          next: TransmissionProcessor(
            connectionString: connectionString,
            httpClient: httpClient ?? http.Client(),
            timeout: const Duration(seconds: 10),
          ),
        ),
      );
    }
  }

  final RequestContentLengthMethod requestContentLengthMethod;
  final ResponseContentLengthMethod responseContentLengthMethod;

  TelemetryClient? _telemetryClient;

  static const startTimeKey =
      'DioAzureApplicationInsightsInterceptor_startTime';
  static const requestContentLengthKey =
      'DioAzureApplicationInsightsInterceptor_requestContextLength';

  @override
  Future onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      options.extra[startTimeKey] = DateTime.timestamp();
      options.extra[requestContentLengthKey] =
          requestContentLengthMethod(options);
    } catch (_) {}
    return super.onRequest(options, handler);
  }

  @override
  Future onResponse(
    Response response,
    ResponseInterceptorHandler handler,
  ) async {
    final requestDuration = response.requestOptions.extra[startTimeKey] == null
        ? Duration(milliseconds: 0)
        : DateTime.timestamp().difference(
            response.requestOptions.extra[startTimeKey]! as DateTime);

    _telemetryClient?.trackDependency(
      name: response.requestOptions.path,
      type: response.requestOptions.uri.scheme,
      resultCode: response.statusCode?.toString() ?? '200',
      target: response.requestOptions.uri.host,
      duration: requestDuration,
      success: response.statusCode?.toString().startsWith('2'),
      data: response.requestOptions.uri.toString(),
      additionalProperties: {
        if (Platform.environment['WEBSITE_SITE_NAME'] != null)
          'ai.cloud.role': Platform.environment['WEBSITE_SITE_NAME']!,
        if (Platform.environment['WEBSITE_SITE_NAME'] != null)
          'appName': Platform.environment['WEBSITE_SITE_NAME']!,
        if (Platform.environment['WEBSITE_OWNER_NAME'] != null)
          'appId': Platform.environment['WEBSITE_OWNER_NAME']!,
      },
    );

    return super.onResponse(response, handler);
  }

  @override
  Future onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final requestDuration = err.requestOptions.extra[startTimeKey] == null
        ? Duration(milliseconds: 0)
        : DateTime.timestamp()
            .difference(err.requestOptions.extra[startTimeKey]! as DateTime);

    _telemetryClient?.trackDependency(
      name: err.response?.requestOptions.path ?? 'unknown',
      type: err.response?.requestOptions.uri.scheme,
      resultCode: err.response?.statusCode?.toString() ?? '500',
      target: err.response?.requestOptions.uri.host,
      duration: requestDuration,
      success: false,
      data: err.response?.requestOptions.uri.toString(),
      additionalProperties: {
        'requestHeaders': jsonEncode(err.requestOptions.headers),
        'requestData': err.requestOptions.data.toString(),
        'responseMessage': err.message ?? 'null',
        'responseData': err.response?.data ?? 'null',
        'responseHeaders':
            jsonEncode(err.response?.headers.map ?? <String, dynamic>{}),
        if (Platform.environment['WEBSITE_SITE_NAME'] != null)
          'ai.cloud.role': Platform.environment['WEBSITE_SITE_NAME']!,
        if (Platform.environment['WEBSITE_SITE_NAME'] != null)
          'appName': Platform.environment['WEBSITE_SITE_NAME']!,
        if (Platform.environment['WEBSITE_OWNER_NAME'] != null)
          'appId': Platform.environment['WEBSITE_OWNER_NAME']!,
      },
    );

    return super.onError(err, handler);
  }
}

typedef RequestContentLengthMethod = int? Function(RequestOptions options);
int? defaultRequestContentLength(RequestOptions options) {
  try {
    return options.headers.toString().length + options.data.toString().length;
  } catch (_) {
    return null;
  }
}

typedef ResponseContentLengthMethod = int? Function(Response options);
int? defaultResponseContentLength(Response response) {
  try {
    String? lengthHeader = response.headers[Headers.contentLengthHeader]?.first;
    int length = int.parse(lengthHeader ?? '-1');
    if (length <= 0) {
      int headers = response.headers.toString().length;
      length = headers + response.data.toString().length;
    }
    return length;
  } catch (_) {
    return null;
  }
}
