/// A hysteresis window avoids switching back for a small latency difference.
enum Transport { vlessReality, hysteria2 }

class NodeHealth {
  const NodeHealth({
    required this.id,
    required this.transport,
    required this.available,
    required this.latencyMs,
  });

  final String id;
  final Transport transport;
  final bool available;
  final int latencyMs;
}

NodeHealth? selectNode(
  List<NodeHealth> nodes, {
  String? currentId,
  int switchThresholdMs = 80,
}) {
  final healthy = nodes.where((n) => n.available && n.latencyMs >= 0).toList()
    ..sort((a, b) {
      final latency = a.latencyMs.compareTo(b.latencyMs);
      return latency != 0 ? latency : a.id.compareTo(b.id);
    });
  if (healthy.isEmpty) return null;
  final best = healthy.first;
  for (final node in healthy) {
    if (node.id == currentId &&
        node.latencyMs <= best.latencyMs + switchThresholdMs) {
      return node;
    }
  }
  return best;
}
