import 'dart:io';
import 'package:hex/hex.dart';
import 'package:gravity_server/app.dart';

void main(List<String> args) {
  final privateKey = HEX.decode(
      (Platform.environment['JWT_PRIVATE_KEY'] ?? args[0]).replaceAll(':', ''));
  final publicKey = HEX.decode(
      (Platform.environment['JWT_PUBLIC_KEY'] ?? args[1]).replaceAll(':', ''));
  serve(
    App(privateKey: privateKey, publicKey: publicKey).router,
    InternetAddress.anyIPv4,
    int.parse(Platform.environment['PORT'] ?? '8081'),
  );
  print('Gravity Server: start listening.');
  print(HEX.encode(publicKey));
}
