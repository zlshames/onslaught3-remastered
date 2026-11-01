import 'dart:ui';

/// Golden device sizes (logical px) from the golden-tests skill.
abstract final class GoldenDevices {
  /// iPhone 17 Pro landscape.
  static const phone = Size(874, 402);

  /// The Pixel 10 AVD (2424×1080 at 2.625).
  static const phoneSmall = Size(923, 411);

  /// iPad Pro 11" landscape.
  static const tablet = Size(1210, 834);
  static const desktop = Size(1280, 720);

  /// The landscape sizes every existing golden is drawn at.
  static const all = {
    'phone': phone,
    'phoneSmall': phoneSmall,
    'tablet': tablet,
    'desktop': desktop,
  };

  /// iPhone SE (3rd gen) landscape: the narrowest landscape phone.
  static const phoneSE = Size(667, 375);

  /// iPad (10th gen) landscape.
  static const ipad10 = Size(1180, 820);

  /// A 16:10 laptop.
  static const laptop = Size(1440, 900);

  /// More landscape sizes (D5), for new goldens and layout tests.
  static const landscapeExtra = {'phoneSE': phoneSE, 'ipad10': ipad10, 'laptop': laptop};

  /// iPhone 17 Pro portrait.
  static const phonePortrait = Size(402, 874);

  /// iPhone SE portrait: the smallest portrait phone.
  static const phoneSmallPortrait = Size(375, 667);

  /// iPad Pro 11" portrait.
  static const tabletPortrait = Size(834, 1210);

  /// Portrait sizes, for new goldens.
  static const portrait = {
    'phonePortrait': phonePortrait,
    'phoneSmallPortrait': phoneSmallPortrait,
    'tabletPortrait': tabletPortrait,
  };
}
