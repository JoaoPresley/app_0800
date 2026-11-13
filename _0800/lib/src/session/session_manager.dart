import 'package:_0800/src/api/api.dart';

class SessionManager {
  // Construtor privado para Singleton
  SessionManager._internal();

  static final SessionManager instance = SessionManager._internal();

  String? _user;
  String? _password;
  Api? _api;

  String? get user => _user;
  String? get password => _password;
  Api? get api => _api;

  bool get isLoggedIn => _user != null && _password != null && _api != null;

  void setSession({
    required String user,
    required String password,
    required Api api,
  }) {
    _user = user;
    _password = password;
    _api = api;
  }

  void clearSession() {
    _user = null;
    _password = null;
    _api = null;
  }
}
