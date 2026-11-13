import '../lib/api.dart';

void main(List<String> arguments) async {
  final api = Api();
  await api.horas();
}
