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
      final connectionStringElements = connectionString.split(';');

      final instrumentationKeyCandidates = connectionStringElements
          .where((e) => e.startsWith('InstrumentationKey='))
          .toList();

      // if we get an incorrect connection string, don't log anything
      if (instrumentationKeyCandidates.isEmpty) {
        return;
      }

      final instrumentationKey = instrumentationKeyCandidates.first
          .substring('InstrumentationKey='.length);

      _telemetryClient = TelemetryClient(
        processor: BufferedProcessor(
          next: TransmissionProcessor(
            instrumentationKey: instrumentationKey,
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

    _telemetryClient?.trackRequest(
      id: response.hashCode.toString(),
      duration: requestDuration,
      responseCode: response.statusCode?.toString() ?? '200',
      url: response.requestOptions.uri.toString(),
      additionalProperties: {
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

    _telemetryClient?.trackRequest(
      id: err.response.hashCode.toString(),
      duration: requestDuration,
      responseCode: err.response?.statusCode?.toString() ?? '500',
      success: false,
      url: err.response?.requestOptions.uri.toString(),
      additionalProperties: {
        'requestHeaders': jsonEncode(err.requestOptions.headers.map),
        'requestData': err.requestOptions.data,
        'responseMessage': err.message ?? 'null',
        'responseData': err.response?.data,
        'responseHeaders': jsonEncode(err.response?.headers.map),
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
