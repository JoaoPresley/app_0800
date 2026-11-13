import 'dart:io';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

class Api {
  late final Dio _dio;
  late final CookieJar _cookieJar;

  String? currentRf;

  Api() {
    _dio = Dio(
      BaseOptions(
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
          'Accept-Language': 'pt-BR,pt;q=0.9,en-US;q=0.8,en;q=0.7',
        },
        // O segredo: desabilitamos followRedirects para o interceptor de cookies salvar o cookie a cada 302!
        followRedirects: false,
        validateStatus: (status) => status != null && status < 600,
      ),
    );

    _cookieJar = CookieJar();
    _dio.interceptors.add(CookieManager(_cookieJar));

    // Certificado SSL corporativo
    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.badCertificateCallback = (cert, host, port) => true;
        return client;
      },
    );
  }

  /// Inicia o fluxo OAuth/OIDC seguindo os redirects e coletando o cookie de sessão e o parâmetro 'rf'
  Future<void> initSession() async {
    String currentUrl = 'https://ifs10pro.msgas.com.br:48080/main/ifsapplications/web/';

    try {
      // Iniciando HandShake para login
      for (int step = 1; step <= 4; step++) { // Máxima de 3 interações
        // 1. Obtem a resposta da requisição
        final response = await _dio.get(currentUrl);

        // 1.1. Se a resposta foi positiva..
        if (response.statusCode == 200) {
          // Faz o POST com o usuário e senha
          //  1.1.1 Link do login
          final location = response.headers.value('location').toString();
          final uri = Uri.parse(currentUrl).resolve(location);
          

          return;
        }

        // 1.2 Se foi um redirecionamento..
        final location = response.headers.value('location'); //Obtem link do redirecionamento
        if (location != null &&
            (response.statusCode == 301 ||
             response.statusCode == 302 ||
             response.statusCode == 303 ||
             response.statusCode == 307)) {
          // Nova requisição
          final uri = Uri.parse(currentUrl).resolve(location);
          currentUrl = uri.toString();
        } else {
          throw Exception('EXCEPTION: Interrompido com status: ${response.statusCode}');
        }
      }
      // Se realizou 3 interações e não conseguiu fazer o login
      throw Exception("EXCEPTION: 3 redirecionamentos realizado e não conseguiu realizar o login...");
    } catch (e) {
      print('Erro ao obter sessão: $e');
    }
  }

  /// Exemplo de chamada de login (submissão de credenciais com o rf capturado)
  Future<void> login() async {
    final success = await initSession();
    if (!success || currentRf == null) {
      print('Falha ao inicializar sessão para login.');
      return;
    }

    print('Pronto para submeter usuário e senha com rf=$currentRf!');
  }
}
