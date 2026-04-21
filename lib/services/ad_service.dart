import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:startapp_sdk/startapp.dart';

class AdService extends ChangeNotifier {
  static final AdService instance = AdService._internal();

  AdService._internal();

  StartAppSdk? _sdk;
  bool _isInitialized = false;
  bool _isEnabled = true;

  // Configuration
  static const String startAppId = '207904245';

  // Ad states
  StartAppBannerAd? _bannerAd;
  bool _isBannerAdLoading = false;

  StartAppInterstitialAd? _interstitialAd;
  bool _isInterstitialAdLoading = false;

  // Getters
  StartAppSdk? get sdk => _sdk;
  bool get isInitialized => _isInitialized;
  bool get isEnabled => _isEnabled;
  StartAppBannerAd? get bannerAd => _bannerAd;
  bool get isBannerAdLoading => _isBannerAdLoading;
  bool get isInterstitialAdLoading => _isInterstitialAdLoading;
  bool get isBannerLoaded => _bannerAd != null;

  Widget getBannerAd() {
    if (!_isEnabled || _bannerAd == null) return const SizedBox.shrink();
    return StartAppBanner(_bannerAd!);
  }

  Future<void> initialize({StartAppSdk? sdk, bool enabled = true}) async {
    _isEnabled = enabled;
    if (_isInitialized) return;
    _sdk = sdk ?? StartAppSdk();
    
    // Explicitly disable test ads to ensure real ads are shown in production/release.
    // In debug mode, the platform SDK might still show test ads.
    await _sdk!.setTestAdsEnabled(false);

    _isInitialized = true;
    debugPrint('Start.io SDK Initialized with ID: $startAppId (Enabled: $_isEnabled)');

    if (_isEnabled && !kIsWeb) {
      loadInterstitialAd();
    }
  }

  void updateEnabledStatus(bool enabled) {
    _isEnabled = enabled;
    if (_isEnabled) {
      loadInterstitialAd();
    } else {
      _interstitialAd = null;
      _bannerAd = null;
    }
    notifyListeners();
  }

  Future<void> loadBannerAd() async {
    if (!_isEnabled || _isBannerAdLoading || kIsWeb) return;

    _isBannerAdLoading = true;
    notifyListeners();

    _sdk!.loadBannerAd(StartAppBannerType.BANNER).then((ad) {
      _bannerAd = ad;
      _isBannerAdLoading = false;
      notifyListeners();
    }).catchError((ex) {
      debugPrint('Error loading banner ad: $ex');
      _isBannerAdLoading = false;
      notifyListeners();
    });
  }

  Future<void> loadInterstitialAd() async {
    if (!_isEnabled || _isInterstitialAdLoading || kIsWeb) return;

    _isInterstitialAdLoading = true;
    notifyListeners();

    _sdk!
        .loadInterstitialAd(
      onAdDisplayed: () {
        debugPrint('Interstitial ad displayed');
      },
      onAdNotDisplayed: () {
        debugPrint('Interstitial ad not displayed');
        _interstitialAd = null;
        _isInterstitialAdLoading = false;
        loadInterstitialAd();
      },
      onAdClicked: () {
        debugPrint('Interstitial ad clicked');
      },
      onAdHidden: () {
        debugPrint('Interstitial ad hidden');
        _interstitialAd = null;
        _isInterstitialAdLoading = false;
        loadInterstitialAd();
      },
    )
        .then((ad) {
      _interstitialAd = ad;
      _isInterstitialAdLoading = false;
      notifyListeners();
    }).catchError((ex) {
      debugPrint('Error loading interstitial ad: $ex');
      _isInterstitialAdLoading = false;
      notifyListeners();
    });
  }

  Future<bool> showInterstitialAd() async {
    if (!_isEnabled || _interstitialAd == null) return false;

    final result = await _interstitialAd!.show();
    if (result) {
      _interstitialAd = null;
      loadInterstitialAd();
    }
    return result;
  }

  void disposeAds() {
    _bannerAd?.dispose();
    _interstitialAd?.dispose();
    _bannerAd = null;
    _interstitialAd = null;
    notifyListeners();
  }
}
