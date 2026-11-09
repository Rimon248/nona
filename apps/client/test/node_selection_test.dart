import 'package:flutter_test/flutter_test.dart';
import 'package:nona_client/node_selection.dart';

void main() {
  test('fails over when current node is unavailable', () {
    final nodes = [
      const NodeHealth(id: 'a', transport: Transport.vlessReality, available: false, latencyMs: 20),
      const NodeHealth(id: 'b', transport: Transport.hysteria2, available: true, latencyMs: 70),
    ];
    expect(selectNode(nodes, currentId: 'a')?.id, 'b');
  });

  test('keeps current node inside hysteresis window', () {
    final nodes = [
      const NodeHealth(id: 'a', transport: Transport.vlessReality, available: true, latencyMs: 110),
      const NodeHealth(id: 'b', transport: Transport.hysteria2, available: true, latencyMs: 70),
    ];
    expect(selectNode(nodes, currentId: 'a')?.id, 'a');
  });

  test('returns no node when all probes fail', () {
    expect(selectNode([
      const NodeHealth(id: 'a', transport: Transport.vlessReality, available: false, latencyMs: 0),
    ]), isNull);
  });
}
