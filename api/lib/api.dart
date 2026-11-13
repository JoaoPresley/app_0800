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

  bool get isAuthenticated => xsrfToken != null;

  /// Garante que exista uma sessão autenticada antes de qualquer chamada
  Future<bool> ensureAuthenticated() async {
    if (isAuthenticated) return true;
    return await login();
  }

  late final String user;
  late final String password;

  // Constructor
  Api() {
    // 1. Carrega as credenciais do .env (tenta local ou diretório acima)
    final env = DotEnv(includePlatformEnvironment: true);
    if (File('.env').existsSync()) {
      env.load(['.env']);
    } else if (File('api/.env').existsSync()) {
      env.load(['api/.env']);
    } else if (File('../.env').existsSync()) {
      env.load(['../.env']);
    } else {
      env.load();
    }
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
  Future<bool> _initSession() async {
    String currentUrl = 'https://ifs10pro.msgas.com.br:48080/main/ifsapplications/web/';

    try {
      // 1. Inicia requisição
      var response = await _dio.get(currentUrl);
      response = await _redirect(response);
      // Se encontrou a tela de login (200 OK)
      if (response.statusCode == 200) {
        loginUrl = response.realUri.toString();

        if (response.realUri.toString().contains('rf=')) {
          currentRf = response.realUri.queryParameters['rf'];
        }
        return true;
      }else{
        print("Erro ao encontrar página ${response.statusCode}");
        return false;
      }
    } catch (e) {
      print('Erro ao obter sessão: $e');
      return false;
    }
  }

  /// Trata redirecionamentos HTTP (301, 302, 303, 307, 308)
  Future<Response> _redirect(Response response) async {
    // Primeiro status
    int status = response.statusCode ?? 0;
    int breaker = 0;
    // Enquanto tiver redirecionamento ele redireciona
    while ( status == 301 ||
            status == 302 ||
            status == 303 ||
            status == 307 ||
            status == 308) {
              // Se ocorrera 4 interações para
              if (breaker>4) break;
              breaker++;
              // Realiza o redirecionamento
              final location = response.headers.value('location');
              if (location != null && location.isNotEmpty) {
                final currentUri = response.realUri;
                final targetUri = currentUri.resolve(location);
                response = await _dio.getUri(targetUri);
              }else{
                return response;
              }
              status = response.statusCode ?? 0;
    }
    // Se não tiver redirecionamento retorna o própio response
    return response;
  }

  /// Passo 2: Executa o POST de login com usuário e senha do .env e processa a cadeia de callbacks
  Future<bool> login() async {
    print("Iniciado Login");
    final initialized = await _initSession();
    if (!initialized || loginUrl == null || currentRf == null) {
      print('Falha ao inicializar a sessão do login.');
      return false;
    }

    // 2. Enviando credenciais (POST) para: $loginUrl
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

      // 3. Processa a sequência de callbacks pós-login (Location 302 e OIDC Form Post)
      response = await _redirect(response);

      // Trata o redirecionamento OIDC via Form Auto-Post, se retornado
      if (response.statusCode == 200 && response.data.toString().contains('<form')) {
        final body = response.data.toString();
        final actionMatch = RegExp(r'<form[^>]*action=[\x22\x27]([^\x22\x27]*)[\x22\x27]').firstMatch(body);

        if (actionMatch != null) {
          final action = actionMatch.group(1)!;
          final callbackUrl = response.realUri.resolve(action).toString();

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

          // Segue eventuais redirecionamentos após o POST do form OIDC
          response = await _redirect(response);
        }
      }

      // 4. Captura o cookie XSRF-TOKEN salvo no CookieJar
      print("Buscando cookies");
      final baseUri = Uri.parse('https://ifs10pro.msgas.com.br:48080');
      final cookies = await _cookieJar.loadForRequest(baseUri);
      for (var cookie in cookies) {
        if (cookie.name == 'XSRF-TOKEN') {
          print("Encontrado cookie");
          xsrfToken = cookie.value;
          _dio.options.headers['X-XSRF-TOKEN'] = xsrfToken;
          break;
        }
      }

      // Se não caiu de volta na tela de login com rf=, login foi um sucesso
      final finalUrl = response.realUri.toString();
      if (!finalUrl.contains('login?rf=')) {
        return true;
      } else {
        print('Falha de login: redirecionado de volta para o login. Verifique usuário e senha.');
        return false;
      }
    } catch (e) {
      print('Erro no fluxo de login: $e');
      return false;
    }
  }

  /// Método genérico para requisições GET autenticadas e resilientes
  Future<Response> getData(String url) async {
    print("Realizando requisição $url");
    await ensureAuthenticated();

    var response = await _dio.get(url);
    response = await _redirect(response);

    // Se a sessão expirou ou redirecionou de volta pro login
    if (response.realUri.toString().contains('login?rf=') || response.statusCode == 401) {
      print('Sessão expirada ou não autenticada. Renovando login...');
      xsrfToken = null;
      final reconnected = await login();
      if (reconnected) {
        response = await _dio.get(url);
        response = await _redirect(response);
      }
    }

    return response;
  }

  /// Método genérico para requisições POST autenticadas e resilientes
  Future<Response> postData(String url, {dynamic data, Map<String, dynamic>? headers}) async {
    await ensureAuthenticated();

    Options? options;
    if (headers != null) {
      options = Options(headers: headers);
    }

    var response = await _dio.post(url, data: data, options: options);
    response = await _redirect(response);

    // Se a sessão expirou ou redirecionou de volta pro login
    if (response.realUri.toString().contains('login?rf=') || response.statusCode == 401) {
      print('Sessão expirada ou não autenticada. Renovando login...');
      xsrfToken = null;
      final reconnected = await login();
      if (reconnected) {
        response = await _dio.post(url, data: data, options: options);
        response = await _redirect(response);
      }
    }

    return response;
  }

  /// Método genérico para requisições PATCH autenticadas e resilientes
  Future<Response> patchData(String url, {dynamic data, Map<String, dynamic>? headers}) async {
    await ensureAuthenticated();

    Options? options;
    if (headers != null) {
      options = Options(headers: headers);
    }

    var response = await _dio.patch(url, data: data, options: options);
    response = await _redirect(response);

    if (response.realUri.toString().contains('login?rf=') || response.statusCode == 401) {
      print('Sessão expirada ou não autenticada. Renovando login...');
      xsrfToken = null;
      final reconnected = await login();
      if (reconnected) {
        response = await _dio.patch(url, data: data, options: options);
        response = await _redirect(response);
      }
    }

    return response;
  }

  Future<String> horas() async {
    const url = "https://ifs10pro.msgas.com.br:48080/main/ifsapplications/projection/v1/WorkTaskClockingsHandling.svc/JtTaskClockingSet";
    final response = await getData(url);

    if (response.statusCode == 200) {
      print("Tudo deu certo");
    } else {
      print('Não foi: ${response.statusCode} - ${response.realUri}');
    }

    return response.data.toString();
  }
}
