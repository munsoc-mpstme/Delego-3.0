class Backend {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://mundra.munsocietympstme.com',
  );
}
//http://10.0.2.2:8000" "https://mundra.munsocietympstme.com";