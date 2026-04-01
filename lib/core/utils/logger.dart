import 'package:logger/logger.dart' as log;

final appLogger = log.Logger(
  printer: log.PrettyPrinter(
    methodCount: 2,
    errorMethodCount: 8,
    lineLength: 120,
    colors: true,
    printEmojis: true,
    printTime: true,
  ),
);
