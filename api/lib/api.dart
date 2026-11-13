import 'dart:async';
import 'dart:convert';
import 'dart:io';

class Api {
  final HttpClient _client;
  // Armazena os cookies entre os redirecionamentos
  final Map<String, String> _cookies = {};

  Api({HttpClient? client}) : _client = client ?? HttpClient() {
    // Caso o certificado SSL da rede interna precise ser aceito:
    _client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }

  // Atributos para consulta posterior
  Map<String, String> get cookies => _cookies;
  String? currentRf;

  Future<void> login() async {
    final initialUrl = Uri.parse('https://ifs10pro.msgas.com.br:48080/main/ifsapplications/web/');

    try {
      print('1. Acessando URL inicial...');
      Uri currentUrl = initialUrl;
      String? rf;

      // Segue os redirecionamentos acumulando cookies e capturando parâmetros de URL
      for (int i = 0; i < 10; i++) {
        final request = await _client.getUrl(currentUrl);
        request.followRedirects = false; // Controlamos o redirect manualmente

        // Envia os cookies acumulados
        if (_cookies.isNotEmpty) {
          final cookieHeader = _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
          request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
        }

        final response = await request.close();

        // 1. Armazena cookies recebidos no header Set-Cookie
        for (var cookie in response.cookies) {
          _cookies[cookie.name] = cookie.value;
        }

        print('[$i] Status: ${response.statusCode} -> URL: $currentUrl');

        // Se a URL possuir o parâmetro 'rf', guardamos
        if (currentUrl.queryParameters.containsKey('rf')) {
          rf = currentUrl.queryParameters['rf'];
          currentRf = rf;
          print('>>> Parâmetro rf encontrado: $rf');
        }

        // Verifica se é redirecionamento (301, 302, 303, 307)
        if (response.isRedirect ||
            response.statusCode == 301 ||
            response.statusCode == 302 ||
            response.statusCode == 303 ||
            response.statusCode == 307) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null) {
            print('Redirecionamento sem header Location.');
            break;
          }

          // Resolve URLs relativas caso necessário
          currentUrl = currentUrl.resolve(location);
          print('    Redirecionando para: $currentUrl');
        } else if (response.statusCode == 200) {
          final body = await response.transform(utf8.decoder).join();
          print('Página de Login carregada com sucesso! (${body.length} caracteres)');
          break;
        } else {
          print('Status não tratado: ${response.statusCode}');
          break;
        }
      }

      print('\n--- Resumo ---');
      print('RF capturado: $currentRf');
      print('Cookies capturados: $_cookies');
    } catch (e) {
      print("Erro durante o fluxo: $e");
    }
  }
}
