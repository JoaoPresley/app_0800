import 'dart:io';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:dotenv/dotenv.dart';

class Api {
  late final Dio _dio;
  late final CookieJar _cookieJar;

  String? currentRf;
  String? loginUrl;
  String? xsrfToken;

  late final String user;
  late final String password;

  Api() {
    // 1. Carrega as credenciais do .env
    final env = DotEnv(includePlatformEnvironment: true)..load(['../.env']);
    user = env['USERNAME'] ?? '';
    password = env['PASSWORD'] ?? '';

    // 2. Configura a instância do Dio
    _dio = Dio(
      BaseOptions(
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
          'Accept-Language': 'pt-BR,pt;q=0.9,en-US;q=0.8,en;q=0.7',
        },
        followRedirects: false, // Controle de redirects para salvar cookies em cada salto
        validateStatus: (status) => status != null && status < 600,
      ),
    );

    // 3. CookieJar para manter os cookies da sessão
    _cookieJar = CookieJar();
    _dio.interceptors.add(CookieManager(_cookieJar));

    // 4. Ignora validação de certificados SSL corporativos
    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.badCertificateCallback = (cert, host, port) => true;
        return client;
      },
    );
  }

  /// Passo 1: Handshake OIDC até atingir a página de login com o parâmetro 'rf'
  Future<bool> initSession() async {
    String currentUrl = 'https://ifs10pro.msgas.com.br:48080/main/ifsapplications/web/';

    try {
      // 1. Inicia requisição
      for (int step = 1; step <= 3; step++) {
        final response = await _dio.get(currentUrl);

        // Se encontrou a tela de login (200 OK)
        if (response.statusCode == 200) {
          loginUrl = currentUrl;
          if (currentUrl.contains('rf=')) {
            currentRf = Uri.parse(currentUrl).queryParameters['rf'];
          }
          return true;
        }

        // Se for redirecionamento (301, 302, 303, 307)
        final location = response.headers.value('location');
        if (location != null &&
            (response.statusCode == 301 ||
             response.statusCode == 302 ||
             response.statusCode == 303 ||
             response.statusCode == 307)) {
          final uri = Uri.parse(currentUrl).resolve(location);
          currentUrl = uri.toString();
        } else {
          print('Interrompido no handshake com status: ${response.statusCode}');
          return false;
        }
      }
      print('Realizada 3 redirecionamentos e não foi encontrado tela de login');
      return false;
    } catch (e) {
      print('Erro ao obter sessão: $e');
      return false;
    }
  }

  /// Passo 2: Executa o POST de login com usuário e senha do .env e processa a cadeia de callbacks
  Future<void> login() async {
    final initialized = await initSession();
    if (!initialized || loginUrl == null || currentRf == null) {
      print('Falha ao inicializar a sessão do login.');
      return;
    }

    //2. Enviando credenciais (POST) para: $loginUrl
    try {
      var response = await _dio.post(
        loginUrl!,
        data: {
          'username': user,
          'password': password,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {
            'Referer': loginUrl,
            'Origin': 'https://ifs10pro.msgas.com.br:48080',
          },
        ),
      );

      String currentUrl = loginUrl!;

      // 3. Processa a sequência de callbacks pós-login (Location 302 e OIDC Form Post)
      for (int step = 1; step <= 6; step++) {
        final location = response.headers.value('location');

        // Redireciona
        //  Se for um redirecionamento comum
        if (location != null &&
            (response.statusCode == 301 ||
             response.statusCode == 302 ||
             response.statusCode == 303 ||
             response.statusCode == 307)) {
          final nextUri = Uri.parse(currentUrl).resolve(location);
          currentUrl = nextUri.toString();
          response = await _dio.get(currentUrl);
          // Se o redirecionamento estiver no corpo da requisição
        } else if (response.statusCode == 200 && response.data.toString().contains('<form')) {
          // O OIDC costuma devolver uma página com um formulário auto-post (id_token, state)
          final body = response.data.toString();
          final actionMatch = RegExp(r'<form[^>]*action=[\x22\x27]([^\x22\x27]*)[\x22\x27]').firstMatch(body);

          if (actionMatch != null) {
            final action = actionMatch.group(1)!;
            final callbackUrl = Uri.parse(currentUrl).resolve(action).toString();

            final Map<String, String> formData = {};
            final inputMatches = RegExp(r'<input[^>]*name=[\x22\x27]([^\x22\x27]*)[\x22\x27][^>]*value=[\x22\x27]([^\x22\x27]*)[\x22\x27]').allMatches(body);
            for (var m in inputMatches) {
              formData[m.group(1)!] = m.group(2)!;
            }

            response = await _dio.post(
              callbackUrl,
              data: formData,
              options: Options(contentType: Headers.formUrlEncodedContentType),
            );
            currentUrl = callbackUrl;
          } // Se não foi um status 30x ou 200 com form não é redirecionamento
           else {
            break;
          }
        } else {
          break;
        }
      }
    } catch (e) {
      print('Erro no fluxo de login: $e');
    }
  }

  
}
