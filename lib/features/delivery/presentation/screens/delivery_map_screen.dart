import 'package:flutter/material.dart';
import '../delivery_theme.dart';

class DeliveryMapScreen extends StatefulWidget {
  const DeliveryMapScreen({super.key});

  @override
  State<DeliveryMapScreen> createState() => _DeliveryMapScreenState();
}

class _DeliveryMapScreenState extends State<DeliveryMapScreen> {
  // TODO: replace with API call
  static const _mockPickup = 'Farmgate Agro Market, Dhaka';
  static const _mockDrop = 'Mirpur-10 Poultry Hub, Dhaka';
  static const _mockDistance = '4.2 km';
  static const _mockEta = '18 min';
  bool _isRouteOptimized = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DColors.bg,
      appBar: AppBar(
        backgroundColor: DColors.appBar,
        elevation: 0,
        title: const Text(
          'Map',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white38),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.directions_bike,
                      color: Colors.white, size: 13),
                  SizedBox(width: 4),
                  Text('On The Way',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildMapArea()),
          _buildBottomPanel(),
        ],
      ),
    );
  }

  Widget _buildMapArea() {
    return Stack(
      children: [
        Container(
          width: double.infinity,
          color: const Color(0xFFE8F0F7),
          child: CustomPaint(
            painter: _MockMapPainter(),
          ),
        ),
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: _buildRouteOverlay(),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: DColors.cardBorder),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 8,
                    )
                  ],
                ),
                child: const Icon(Icons.map, color: DColors.primary, size: 28),
              ),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 6,
                    )
                  ],
                ),
                child: const Text(
                  'Map preview (mock)',
                  style: TextStyle(
                      color: DColors.textSecondary, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: 80,
          left: MediaQuery.of(context).size.width * 0.3,
          child: _mapPin(DColors.accent, Icons.radio_button_checked),
        ),
        Positioned(
          bottom: 100,
          right: MediaQuery.of(context).size.width * 0.25,
          child: _mapPin(DColors.red, Icons.location_on),
        ),
      ],
    );
  }

  Widget _mapPin(Color color, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2), blurRadius: 6),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
        Container(
          width: 2,
          height: 12,
          color: color.withValues(alpha: 0.7),
        ),
      ],
    );
  }

  Widget _buildRouteOverlay() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: dCard(),
      child: Row(
        children: [
          Column(
            children: [
              const Icon(Icons.radio_button_checked,
                  color: DColors.accent, size: 14),
              Container(width: 1, height: 20, color: DColors.cardBorder),
              const Icon(Icons.location_on, color: DColors.red, size: 14),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_mockPickup,
                    style: const TextStyle(
                        color: DColors.textSecondary, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                Text(_mockDrop,
                    style: const TextStyle(
                        color: DColors.textSecondary, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_mockDistance,
                  style: const TextStyle(
                      color: DColors.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.access_time,
                      color: DColors.grey, size: 11),
                  const SizedBox(width: 3),
                  Text(_mockEta,
                      style: const TextStyle(
                          color: DColors.grey, fontSize: 11)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      decoration: const BoxDecoration(
        color: DColors.bg,
        border: Border(top: BorderSide(color: DColors.cardBorder)),
        boxShadow: [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 10,
            offset: Offset(0, -2),
          )
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _statPill(Icons.straighten, _mockDistance, DColors.accent),
              const SizedBox(width: 10),
              _statPill(Icons.access_time, _mockEta, DColors.textSecondary),
              const Spacer(),
              GestureDetector(
                onTap: () =>
                    setState(() => _isRouteOptimized = !_isRouteOptimized),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: _isRouteOptimized
                        ? DColors.accentLight
                        : DColors.surface2,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _isRouteOptimized
                          ? DColors.accent.withValues(alpha: 0.5)
                          : DColors.cardBorder,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.alt_route,
                          color: _isRouteOptimized
                              ? DColors.accent
                              : DColors.grey,
                          size: 15),
                      const SizedBox(width: 5),
                      Text(
                        _isRouteOptimized ? 'Optimized' : 'Optimize',
                        style: TextStyle(
                          color: _isRouteOptimized
                              ? DColors.accent
                              : DColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      'Opening Google Maps… (mock coords: 23.7461,90.3742 → 23.8041,90.3642)'),
                  behavior: SnackBarBehavior.floating,
                ),
              ),
              icon: const Icon(Icons.navigation, size: 18),
              label: const Text('Navigate',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: DColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statPill(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: dCard(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _MockMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFFD0DCE8)
      ..strokeWidth = 1;

    for (double x = 0; x < size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final roadPaint = Paint()
      ..color = const Color(0xFFBFCDD9)
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
        Offset(size.width * 0.1, size.height * 0.2),
        Offset(size.width * 0.9, size.height * 0.4),
        roadPaint);
    canvas.drawLine(
        Offset(size.width * 0.3, 0),
        Offset(size.width * 0.4, size.height),
        roadPaint);
    canvas.drawLine(
        Offset(0, size.height * 0.6),
        Offset(size.width, size.height * 0.7),
        roadPaint);

    final routePaint = Paint()
      ..color = const Color(0xFF2E7D32).withValues(alpha: 0.8)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(size.width * 0.3, size.height * 0.25)
      ..cubicTo(
        size.width * 0.45, size.height * 0.35,
        size.width * 0.55, size.height * 0.55,
        size.width * 0.72, size.height * 0.68,
      );
    canvas.drawPath(path, routePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
