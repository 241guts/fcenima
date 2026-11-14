import 'package:cinemax_player/src/utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatDuration matches the design (H:MM:SS)', () {
    expect(formatDuration(const Duration(minutes: 15, seconds: 32)), '0:15:32');
    expect(formatDuration(const Duration(hours: 1, minutes: 16, seconds: 32)), '1:16:32');
    expect(formatDuration(Duration.zero), '0:00:00');
  });
}
