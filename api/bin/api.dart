import 'dart:async';

import '../lib/api.dart';
import 'dart:io';

void main(List<String> arguments) async {
  final api = Api();
  final stopwatch = Stopwatch()..start();
  final resp = await api.getData('https://ifs10pro.msgas.com.br:48080/main/ifsapplications/projection/v1/WorkTaskClockingsHandling.svc/JtTaskClockingSet?\$top=5');
  stopwatch.stop();
  print(stopwatch.elapsedMilliseconds);
}
