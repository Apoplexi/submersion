import 'package:connectivity_plus/connectivity_plus.dart';

/// Coarse network classification for transfer policies (design spec
/// section 9). Wifi/ethernet/VPN count as unmetered; a VPN's underlying
/// transport is invisible to the app, so it is treated optimistically.
enum NetworkKind { offline, cellular, unmetered }

class NetworkStatusService {
  NetworkStatusService({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  static NetworkKind kindFrom(List<ConnectivityResult> results) {
    const unmetered = {
      ConnectivityResult.wifi,
      ConnectivityResult.ethernet,
      ConnectivityResult.vpn,
    };
    if (results.any(unmetered.contains)) return NetworkKind.unmetered;
    if (results.contains(ConnectivityResult.mobile)) {
      return NetworkKind.cellular;
    }
    return NetworkKind.offline;
  }

  Future<NetworkKind> current() async =>
      kindFrom(await _connectivity.checkConnectivity());

  Stream<NetworkKind> get changes =>
      _connectivity.onConnectivityChanged.map(kindFrom).distinct();
}
