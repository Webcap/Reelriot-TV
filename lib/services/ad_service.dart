import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:startapp_sdk/startapp.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/ad.dart';
import 'settings_service.dart';

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

  List<Ad> _nativeAds = [];
  List<Ad> get nativeAds {
    final simulate = SettingsService().simulateAds;
    final isDev = kDebugMode; // Simple dev check for TV

    if (simulate && isDev && _nativeAds.isEmpty) {
      return Ad.getSimulatedAds();
    }
    return _nativeAds;
  }

  Future<void> fetchNativeAds() async {
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('sponsorships')
          .select()
          .eq('is_active', true)
          .order('priority', ascending: false);

      _nativeAds = (response as List).map((e) => Ad.fromJson(e)).toList();
      debugPrint('Fetched ${_nativeAds.length} native ads from Supabase (TV)');
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching native ads (TV): $e');
    }
  }

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
    
    // Enable test ads only in debug mode to ensure real ads are shown in production.
    await _sdk!.setTestAdsEnabled(kDebugMode);

    _isInitialized = true;
    debugPrint('Start.io SDK Initialized with ID: $startAppId (Enabled: $_isEnabled)');

    // Fetch native ads
    fetchNativeAds();

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
