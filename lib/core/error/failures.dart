sealed class Failure {
  final String message;
  final int? statusCode;

  const Failure(this.message, {this.statusCode});

  @override
  String toString() => 'Failure($message, statusCode: $statusCode)';
}

class ServerFailure extends Failure {
  const ServerFailure(super.message, {super.statusCode});
}

class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'No internet connection']);
}

class CacheFailure extends Failure {
  const CacheFailure([super.message = 'Cache error']);
}

class BleFailure extends Failure {
  const BleFailure(super.message);
}

class AuthFailure extends Failure {
  const AuthFailure(super.message, {super.statusCode});
}

class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

class TimeoutFailure extends Failure {
  const TimeoutFailure([super.message = 'Request timed out']);
}
