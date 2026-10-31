import 'package:flutter/material.dart';

import '../location/delivery_location.dart';

/// Delivery-location capture for checkout (NF-3): "Use my current location"
/// (GPS) or manual latitude/longitude, with the same validation as the server.
/// Reports a valid [DeliveryLocation] (or null while missing/invalid) through
/// [onChanged]; the parent keeps its submit button disabled until it is non-null.
class DeliveryLocationPicker extends StatefulWidget {
  const DeliveryLocationPicker({
    super.key,
    required this.onChanged,
    this.fetcher = fetchCurrentLocation,
  });

  final ValueChanged<DeliveryLocation?> onChanged;
  final LocationFetcher fetcher;

  @override
  State<DeliveryLocationPicker> createState() => _DeliveryLocationPickerState();
}

class _DeliveryLocationPickerState extends State<DeliveryLocationPicker> {
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  bool _fetching = false;
  bool _manual = false;
  String? _error;
  DeliveryLocation? _location;

  @override
  void dispose() {
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  void _publish(DeliveryLocation? loc, String? error) {
    setState(() {
      _location = loc;
      _error = error;
    });
    widget.onChanged(loc);
  }

  Future<void> _useGps() async {
    setState(() {
      _fetching = true;
      _error = null;
    });
    try {
      final loc = await widget.fetcher();
      final problem = validateDeliveryLocation(loc.lat, loc.lng);
      if (!mounted) return;
      setState(() => _fetching = false);
      if (problem != null) {
        _publish(null, problem);
        return;
      }
      _lat.text = loc.lat.toStringAsFixed(6);
      _lng.text = loc.lng.toStringAsFixed(6);
      _publish(loc, null);
    } on LocationUnavailable catch (e) {
      if (!mounted) return;
      setState(() {
        _fetching = false;
        _manual = true; // fall back to manual entry
      });
      _publish(null, e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _fetching = false;
        _manual = true;
      });
      _publish(null, 'Could not get your location. Enter coordinates manually.');
    }
  }

  void _onManualChanged() {
    final parsed = parseManualLocation(_lat.text, _lng.text);
    if (parsed.error != null || parsed.lat == null || parsed.lng == null) {
      final untouched = _lat.text.trim().isEmpty && _lng.text.trim().isEmpty;
      _publish(null, untouched ? null : parsed.error);
    } else {
      _publish(DeliveryLocation(parsed.lat!, parsed.lng!), null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = _location;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: loc != null ? const Color(0xFF2E7D32) : const Color(0xFFBDBDBD)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Delivery location *', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        const Text('Riders navigate to this point, so it is required.',
            style: TextStyle(fontSize: 11, color: Color(0xFF666666))),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          OutlinedButton.icon(
            key: const Key('useLocationButton'),
            onPressed: _fetching ? null : _useGps,
            icon: _fetching
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location, size: 16),
            label: Text(_fetching ? 'Locating...' : 'Use my current location'),
          ),
          TextButton(
            key: const Key('manualLocationToggle'),
            onPressed: () => setState(() => _manual = !_manual),
            child: Text(_manual ? 'Hide manual entry' : 'Enter coordinates manually'),
          ),
        ]),
        if (_manual) ...[
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: TextField(
                key: const Key('latField'),
                controller: _lat,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                onChanged: (_) => _onManualChanged(),
                decoration: const InputDecoration(labelText: 'Latitude', hintText: 'e.g. 23.8103'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: const Key('lngField'),
                controller: _lng,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                onChanged: (_) => _onManualChanged(),
                decoration: const InputDecoration(labelText: 'Longitude', hintText: 'e.g. 90.4125'),
              ),
            ),
          ]),
        ],
        if (loc != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              const Icon(Icons.check_circle, size: 16, color: Color(0xFF2E7D32)),
              const SizedBox(width: 6),
              Text('Location set: $loc',
                  key: const Key('locationSet'),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!,
                key: const Key('locationError'),
                style: const TextStyle(fontSize: 12, color: Color(0xFFC62828))),
          ),
      ]),
    );
  }
}
