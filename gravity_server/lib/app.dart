import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

export 'package:shelf/shelf_io.dart';

typedef AppParams = ({
  String hasuraAdminKey,
  List<int> publicKey,
  List<int> privateKey,
});

class App {
  static const Map<String, String> contentType = {
    'Content-Type': 'application/json',
  };

  final AppParams params;
  final EdDSAPublicKey publicKey;
  final EdDSAPrivateKey privateKey;

  App(this.params)
      : publicKey = EdDSAPublicKey(params.publicKey),
        privateKey = EdDSAPrivateKey(params.privateKey + params.publicKey);

  Router get router => Router()
    ..post('/user/register', (Request request) async {
      final jwt = await _extractRequest(request);
      // TBD: gql request
      return Response.ok(
        _createJWT('sub'),
        headers: contentType,
      );
    })
    ..post('/user/logon', (Request request) async {
      final jwt = await _extractRequest(request);
      // TBD: gql request
      return Response.ok(
        _createJWT('sub'),
        headers: contentType,
      );
    });

  Future<JWT> _extractRequest(Request request) async {
    final body = await request.readAsString();
    return JWT.verify(
      body,
      ECPublicKey.bytes(base64Decode(JWT.decode(body).subject!)),
    );
  }

  String _createJWT(String sub) => JWT({}, subject: sub).sign(
        privateKey,
        algorithm: JWTAlgorithm.EdDSA,
      );
}
