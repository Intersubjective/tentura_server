import 'dart:io';
import 'package:hex/hex.dart';
import 'package:gravity_server/app.dart';

void main(List<String> arguments) async {
  final params = (
    hasuraAdminKey: Platform.environment['JWT_PRIVATE_KEY']!,
    publicKey:
        HEX.decode(Platform.environment['JWT_PUBLIC_KEY']!.replaceAll(':', '')),
    privateKey: HEX
        .decode(Platform.environment['JWT_PRIVATE_KEY']!.replaceAll(':', '')),
  );
  await serve(
    App(params).router,
    InternetAddress.anyIPv4,
    int.parse(Platform.environment['PORT'] ?? '8081'),
  );
}
