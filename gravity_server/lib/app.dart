import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:graphql/client.dart' as gql;

export 'package:shelf/shelf_io.dart';

typedef AppParams = ({
  String hasuraAdminKey,
  List<int> publicKey,
  List<int> privateKey,
});

class App {
  static const contentType = {'Content-Type': 'application/json'};

  final queryLogin = gql.gql(r'''
query UserFetch($publicKey: String!) {
  user(where: {public_key: {_eq: $publicKey}}) {
    ...UserFields
  }
}
''');
  final queryRegister = gql.gql(r'''
mutation UserCreate($title: String = "", $description: String = "", $publicKey: String!) {
  insert_user_one(object: {title: $title, description: $description, public_key: $publicKey}) {
    ...UserFields
  }
}
''');

  final AppParams params;
  final gql.GraphQLClient client;
  final EdDSAPublicKey publicKey;
  final EdDSAPrivateKey privateKey;

  App(this.params)
      : publicKey = EdDSAPublicKey(params.publicKey),
        privateKey = EdDSAPrivateKey(params.privateKey + params.publicKey),
        client = gql.GraphQLClient(
          cache: gql.GraphQLCache(),
          link: gql.HttpLink(
            'http://hasura/v1/graphql',
            defaultHeaders: {
              ...contentType,
              'x-hasura-admin-secret': params.hasuraAdminKey,
            },
          ),
        );

  Router get router => Router()
    ..post('/user/register', serveRegister)
    ..post('/user/logon', serveLogin);

  Future<Response> serveRegister(Request request) async {
    final jwt = await _extractRequest(request);
    final response = await client.query(gql.QueryOptions(
      document: queryRegister,
      variables: {'publicKey': jwt.subject},
    ));
    return response.data == null || response.hasException
        ? Response.badRequest()
        : Response.ok(
            _createJWT(response.data!['insert_user_one']['id']),
            headers: contentType,
          );
  }

  Future<Response> serveLogin(Request request) async {
    final jwt = await _extractRequest(request);
    final response = await client.query(gql.QueryOptions(
      document: queryLogin,
      variables: {'publicKey': jwt.subject},
    ));
    return response.data == null || response.hasException
        ? Response.badRequest()
        : Response.ok(
            _createJWT(response.data!['user'][0]['id']),
            headers: contentType,
          );
  }

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
