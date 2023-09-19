import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:graphql/client.dart' as gql;

export 'package:shelf/shelf_io.dart';

class App {
  static const contentType = {'Content-Type': 'application/json'};

  static final queryLogin = gql.gql(r'''
query UserFetch($publicKey: String!) {
  user(where: {public_key: {_eq: $publicKey}}) {
    id
  }
}
''');
  static final queryRegister = gql.gql(r'''
mutation UserCreate($title: String = "", $description: String = "", $publicKey: String!) {
  insert_user_one(object: {title: $title, description: $description, public_key: $publicKey}) {
    id
  }
}
''');

  App({
    required List<int> publicKey,
    required List<int> privateKey,
  })  : publicKey = EdDSAPublicKey(publicKey),
        privateKey = EdDSAPrivateKey(privateKey + publicKey);

  final EdDSAPublicKey publicKey;
  final EdDSAPrivateKey privateKey;

  late final adminJWT = JWT({
    'admin': true,
    'sub': 'admin',
  }).sign(
    privateKey,
    algorithm: JWTAlgorithm.EdDSA,
    expiresIn: const Duration(days: 365),
  );

  late final gql.GraphQLClient _client = gql.GraphQLClient(
    cache: gql.GraphQLCache(),
    link: gql.HttpLink(
      'http://hasura/v1/graphql',
      defaultHeaders: {
        ...contentType,
        'X-Hasura-Role': 'admin',
        'Authorization': 'Bearer $adminJWT',
      },
    ),
  );

  Router get router => Router()
    ..post('/user/register', serveRegister)
    ..post('/user/logon', serveLogin);

  Future<Response> serveRegister(Request request) async {
    final jwt = await _extractRequest(request);
    final response = await _client.query(gql.QueryOptions(
      document: queryRegister,
      variables: {'publicKey': jwt.subject},
    ));
    return response.data == null || response.hasException
        ? Response.badRequest()
        : Response.ok(
            createJWT(response.data!['insert_user_one']['id']),
            headers: contentType,
          );
  }

  Future<Response> serveLogin(Request request) async {
    final jwt = await _extractRequest(request);
    final response = await _client.query(gql.QueryOptions(
      document: queryLogin,
      variables: {'publicKey': jwt.subject},
    ));
    return response.data == null || response.hasException
        ? Response.badRequest()
        : Response.ok(
            createJWT(response.data!['user'][0]['id']),
            headers: contentType,
          );
  }

  String createJWT(String sub) => JWT({}, subject: sub).sign(
        privateKey,
        algorithm: JWTAlgorithm.EdDSA,
        expiresIn: const Duration(hours: 1),
      );

  Future<JWT> _extractRequest(Request request) async {
    final body = await request.readAsString();
    return JWT.verify(
      body,
      ECPublicKey.bytes(base64Decode(JWT.decode(body).subject!)),
    );
  }
}
