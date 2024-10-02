import 'package:dio/dio.dart';
import 'package:dio_azure_application_insights_interceptor/dio_azure_application_insights_interceptor.dart';

void main() {
  final dio = Dio();
  final insightsInterceptor = DioAzureApplicationInsightsInterceptor();
  dio.interceptors.add(insightsInterceptor);
}
