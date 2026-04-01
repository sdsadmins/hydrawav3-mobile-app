class ServerException implements Exception {
  final String message;
  final int? statusCode;

  const ServerException(this.message, {this.statusCode});

  @override
  String toString() => 'ServerException($message, statusCode: $statusCode)';
}

class CacheException implements Exception {
  final String message;

  const CacheException([this.message = 'Cache error']);

  @override
  String toString() => 'CacheException($message)';
}

class AuthException implements Exception {
  final String message;
  final int? statusCode;

  const AuthException(this.message, {this.statusCode});

  @override
  String toString() => 'AuthException($message)';
}

class BleException implements Exception {
  final String message;

  const BleException(this.message);

  @override
  String toString() => 'BleException($message)';
}
