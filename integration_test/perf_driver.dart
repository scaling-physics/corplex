// Driver for `integration_test/perf_test.dart` when it must run in profile
// mode (`flutter test` has no --profile):
//
//   flutter drive --driver=integration_test/perf_driver.dart \
//     --target=integration_test/perf_test.dart -d macos --profile
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
