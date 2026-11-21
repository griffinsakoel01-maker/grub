/// App-wide configuration.
class AppConfig {
  static const appName = 'Grub';
  static const tagline = 'PLAN MEALS. SHOP SMARTER.';

  /// Region of the Cloud Functions (must match functions/src/index.ts).
  static const functionsRegion = 'africa-south1';

  /// Set at startup: true when Firebase initialised successfully.
  static bool firebaseReady = false;

  /// True after the full logo animation has been seen once on this device.
  static bool introSeen = false;
}
