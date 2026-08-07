import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/services/media_store/network_status_service.dart';

void main() {
  test('kindFrom maps connectivity results', () {
    expect(
      NetworkStatusService.kindFrom([ConnectivityResult.wifi]),
      NetworkKind.unmetered,
    );
    expect(
      NetworkStatusService.kindFrom([ConnectivityResult.ethernet]),
      NetworkKind.unmetered,
    );
    expect(
      NetworkStatusService.kindFrom([
        ConnectivityResult.vpn,
        ConnectivityResult.mobile,
      ]),
      NetworkKind.unmetered,
    );
    expect(
      NetworkStatusService.kindFrom([ConnectivityResult.mobile]),
      NetworkKind.cellular,
    );
    expect(
      NetworkStatusService.kindFrom([ConnectivityResult.none]),
      NetworkKind.offline,
    );
    expect(NetworkStatusService.kindFrom(const []), NetworkKind.offline);
  });
}
