import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

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

      // Resolve a human-readable place name over plain HTTP rather than the
      // `geocoding` native plugin — that plugin broke the Android build and
      // doesn't work on web at all. An HTTP call needs no native code, works
      // identically on mobile and web, and degrades gracefully: if it fails
      // we simply fall back to coordinates rather than losing the location.
      final place = await _reverseGeocode(pos.latitude, pos.longitude) ??
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

  /// Turns coordinates into "City, Region" using BigDataCloud's free
  /// reverse-geocoding endpoint (no API key, no signup, CORS-enabled so it
  /// works on web too).
  ///
  /// Returns null on any failure — a missing city name must never stop the
  /// location itself from being saved, so every error path is swallowed and
  /// the caller falls back to coordinates.
  Future<String?> _reverseGeocode(double lat, double lon) async {
    try {
      final uri = Uri.parse(
          'https://api.bigdatacloud.net/data/reverse-geocode-client'
          '?latitude=$lat&longitude=$lon&localityLanguage=en');
      final res =
          await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body);
      if (data is! Map) return null;

      // Prefer the most specific sensible name available.
      final city = (data['city'] ?? data['locality'] ?? '').toString().trim();
      final region = (data['principalSubdivision'] ?? '').toString().trim();
      final country = (data['countryName'] ?? '').toString().trim();

      final parts = <String>[
        if (city.isNotEmpty) city,
        if (region.isNotEmpty && region != city) region,
      ];
      if (parts.isEmpty && country.isNotEmpty) parts.add(country);

      return parts.isEmpty ? null : parts.join(', ');
    } catch (_) {
      // Offline, timeout, rate-limited, unexpected payload — all fine.
      return null;
    }
  }

  /// Opens the OS settings page so a user who declined can turn it on later.
  Future<void> openSettings() => Geolocator.openAppSettings();
}
