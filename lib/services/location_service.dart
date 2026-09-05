import 'package:geolocator/geolocator.dart';

/// Result of a location attempt. [granted] false means the user declined or
/// the OS blocked it — in that case we store nothing and show an "enable
/// location" prompt instead. Location is entirely optional throughout.
class LocationResult {
  final bool granted;
  final double? latitude;
  final double? longitude;
  final String? placeName;
  final String? timeZoneName;
  final String? error;

  const LocationResult({
    required this.granted,
    this.latitude,
    this.longitude,
    this.placeName,
    this.timeZoneName,
    this.error,
  });

  static const denied = LocationResult(granted: false);
}

class LocationService {
  /// Whether permission is already granted, without prompting.
  Future<bool> hasPermission() async {
    final p = await Geolocator.checkPermission();
    return p == LocationPermission.always || p == LocationPermission.whileInUse;
  }

  /// Requests permission (if needed) and resolves the current place.
  /// Never throws — returns a LocationResult with granted:false instead, so
  /// declining is a normal path rather than an error the UI has to handle.
  Future<LocationResult> requestAndResolve() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationResult(
            granted: false, error: 'Location services are turned off.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return LocationResult.denied;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low, // city-level is all we need
        ),
      );

      // A short coordinate label. We deliberately do NOT use the `geocoding`
      // plugin to turn this into a city name: it's a native plugin that adds
      // build complexity for a cosmetic gain. The timezone + coordinates
      // already satisfy "show location with date and time". To add city
      // names later: `flutter pub add geocoding`, then call
      // placemarkFromCoordinates() here.
      final place =
          '${pos.latitude.toStringAsFixed(3)}, ${pos.longitude.toStringAsFixed(3)}';

      return LocationResult(
        granted: true,
        latitude: pos.latitude,
        longitude: pos.longitude,
        placeName: place,
        // The device's own zone is more reliable than deriving one from
        // coordinates, and needs no extra service.
        timeZoneName: DateTime.now().timeZoneName,
      );
    } catch (e) {
      return LocationResult(granted: false, error: e.toString());
    }
  }

  /// Opens the OS settings page so a user who declined can turn it on later.
  Future<void> openSettings() => Geolocator.openAppSettings();
}
