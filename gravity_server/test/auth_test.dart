import 'dart:convert';
import 'package:hex/hex.dart';
import 'package:http/http.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import 'package:test/test.dart';
import 'package:gravity_server/app.dart';

final _prvKey = HEX.decode(''
        '56:86:b1:32:2f:af:c5:2e:b8:10:32:6b:61:e7:21:af'
        '4f:b0:78:0b:17:8f:ff:a0:58:ec:f0:23:77:28:20:c6'
    .replaceAll(':', ''));
final _pubKey = HEX.decode(''
        '22:33:ca:73:22:3a:d9:f8:62:34:0e:c2:00:e5:a3:06'
        '5b:69:35:84:ae:f6:bf:df:47:01:13:9b:77:7b:b2:97'
    .replaceAll(':', ''));

final params = (
  hasuraAdminKey: '-----BEGIN PUBLIC KEY-----\n'
      'MCowBQYDK2VwAyEAPdY7qqtzhTWVbxB3QkSZ+ENB5nkr9EB4b5AdSdggZ/U=\n'
      '-----END PUBLIC KEY-----',
  publicKey: HEX.decode(''
          '3d:d6:3b:aa:ab:73:85:35:95:6f:10:77:42:44:99:f8'
          '43:41:e6:79:2b:f4:40:78:6f:90:1d:49:d8:20:67:f5'
      .replaceAll(':', '')),
  privateKey: HEX.decode(''
          'c5:8a:79:f1:b5:41:3f:17:6e:84:dd:5a:a4:13:a0:56'
          'ce:6c:c7:52:0d:5d:f8:33:0f:dd:83:a9:dc:9f:7e:2a'
      .replaceAll(':', '')),
);

void main() {
  final jwt = JWT({}, subject: base64Encode(_pubKey)).sign(
    EdDSAPrivateKey(_prvKey + _pubKey),
    algorithm: JWTAlgorithm.EdDSA,
  );

  test('sign/verify', () {
    print(jwt);
    JWT.verify(jwt, EdDSAPublicKey(_pubKey));
  });

  test('register', () async {
    final resp = await post(
      Uri.http('localhost', 'user/register'),
      headers: App.contentType,
      body: jwt,
    );
    print(resp.body);
  });

  test('login', () async {
    final resp = await post(
      Uri.http('localhost', 'user/login'),
      headers: App.contentType,
      body: jwt,
    );
    print(resp.body);
  });
}
