import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/auto_update/domain/entities/release_channel.dart';
import 'package:submersion/features/auto_update/presentation/providers/update_providers.dart';

void main() {
  test('stable channel uses the main repo appcast', () {
    expect(
      appcastUrlFor(ReleaseChannel.stable),
      'https://github.com/submersion-app/submersion/releases/latest/download/appcast.xml',
    );
    expect(githubRepoFor(ReleaseChannel.stable), 'submersion');
  });

  test('beta channel uses the beta-builds superset feed and repo', () {
    expect(
      appcastUrlFor(ReleaseChannel.beta),
      'https://github.com/submersion-app/beta-builds/releases/latest/download/appcast-beta.xml',
    );
    expect(githubRepoFor(ReleaseChannel.beta), 'beta-builds');
  });
}
