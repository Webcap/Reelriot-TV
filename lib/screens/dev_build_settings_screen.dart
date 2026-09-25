import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:reelriot_tv/env.dart';
import 'package:reelriot_tv/screens/update_screen.dart';
import 'package:reelriot_tv/services/beta_service.dart';
import 'package:reelriot_tv/services/update_service.dart';
import 'package:reelriot_tv/theme/dashboard_theme.dart';
import 'package:reelriot_tv/utils/responsive_utils.dart';
import 'package:reelriot_tv/utils/tv_keys.dart';
import 'package:reelriot_tv/widgets/long_press_focus.dart';

/// Screen for managing Developer and Beta build channel memberships on TV.
class DevBuildSettingsScreen extends StatefulWidget {
  const DevBuildSettingsScreen({super.key});

  @override
  State<DevBuildSettingsScreen> createState() => _DevBuildSettingsScreenState();
}

class _DevBuildSettingsScreenState extends State<DevBuildSettingsScreen> {
  final TextEditingController _keyController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final FocusNode _activateFocusNode = FocusNode();
  final FocusNode _checkUpdateFocusNode = FocusNode();
  final FocusNode _clearBetaFocusNode = FocusNode();

  String _currentChannel = 'stable';
  String? _currentKey;
  String _appVersion = '';
  String _buildNumber = '';
  bool _isLoading = false;
  String? _statusMessage;
  bool _isSuccessMessage = false;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  @override
  void dispose() {
    _keyController.dispose();
    _inputFocusNode.dispose();
    _activateFocusNode.dispose();
    _checkUpdateFocusNode.dispose();
    _clearBetaFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadState() async {
    final pkg = await PackageInfo.fromPlatform();
    final ch = await BetaService.getBuildChannel();
    final key = await BetaService.getBetaKey();

    if (mounted) {
      setState(() {
        _appVersion = pkg.version;
        _buildNumber = pkg.buildNumber;
        _currentChannel = ch;
        _currentKey = key;
        if (key != null && key.isNotEmpty) {
          _keyController.text = key;
        }
      });
    }
  }

  Future<void> _activateBetaChannel() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() {
        _statusMessage = 'Enter a valid beta access key';
        _isSuccessMessage = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    try {
      // Test key against the beta channel
      final info = await UpdateService().checkForUpdate(
        caffeineApiUrl,
        env: environment,
        buildChannel: 'beta',
        betaKey: key,
        apiKey: caffeineApiKey,
      );

      // Save key and switch channel
      await BetaService.setBetaKey(key);
      await BetaService.setBuildChannel('beta');

      if (mounted) {
        setState(() {
          _currentChannel = 'beta';
          _currentKey = key;
          _isLoading = false;
          _isSuccessMessage = true;
          _statusMessage = info.isUpdateAvailable
              ? 'Beta activated: Update ${info.latestVersion} available'
              : 'Beta channel activated';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isSuccessMessage = false;
          _statusMessage = 'Activation failed: $e';
        });
      }
    }
  }

  Future<void> _checkForChannelUpdate() async {
    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    try {
      final info = await UpdateService().checkForUpdate(
        caffeineApiUrl,
        env: environment,
        buildChannel: _currentChannel,
        betaKey: _currentKey,
        apiKey: caffeineApiKey,
      );

      if (!mounted) return;

      setState(() => _isLoading = false);

      if (info.isUpdateAvailable && info.downloadUrl != null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => UpdateScreen(
              updateInfo: info,
            ),
          ),
        );
      } else {
        setState(() {
          _isSuccessMessage = true;
          _statusMessage = 'Channel is up to date (${info.currentVersion})';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isSuccessMessage = false;
          _statusMessage = 'Check failed: $e';
        });
      }
    }
  }

  Future<void> _resetToStable() async {
    await BetaService.clearBeta();
    if (mounted) {
      setState(() {
        _currentChannel = 'stable';
        _currentKey = null;
        _keyController.clear();
        _isSuccessMessage = true;
        _statusMessage = 'Reset to stable channel';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    double s(double v) => ResponsiveUtils.scale(context, v);

    final isBeta = _currentChannel == 'beta';
    final isDev = _currentChannel == 'dev';
    final isStable = _currentChannel == 'stable';

    final Color channelColor = isBeta
        ? DashboardTheme.warningAmber
        : isDev
            ? DashboardTheme.infoBlue
            : DashboardTheme.successGreen;

    return Scaffold(
      backgroundColor: DashboardTheme.canvasBlack,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: s(80), vertical: s(48)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  LongPressFocus(
                    onTap: () => Navigator.of(context).pop(),
                    child: Builder(builder: (context) {
                      final focused = Focus.of(context).hasFocus;
                      return Container(
                        padding: EdgeInsets.all(s(12)),
                        decoration: BoxDecoration(
                          color: focused
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.arrow_back,
                          color: focused ? Colors.black : Colors.white,
                          size: s(28),
                        ),
                      );
                    }),
                  ),
                  SizedBox(width: s(24)),
                  Text(
                    'BUILD CHANNELS',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: s(28),
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const Spacer(),
                  // Active Channel Pill
                  Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: s(16), vertical: s(8)),
                    decoration: BoxDecoration(
                      color: channelColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(s(20)),
                      border: Border.all(
                        color: channelColor.withValues(alpha: 0.6),
                        width: s(1.5),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isStable
                              ? Icons.check_circle_outline
                              : Icons.science_outlined,
                          color: channelColor,
                          size: s(18),
                        ),
                        SizedBox(width: s(8)),
                        Text(
                          _currentChannel.toUpperCase(),
                          style: TextStyle(
                            color: channelColor,
                            fontSize: s(14),
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              SizedBox(height: s(40)),

              // Build Info Card
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(s(24)),
                decoration: BoxDecoration(
                  color: DashboardTheme.surface,
                  borderRadius: BorderRadius.circular(s(16)),
                  border: Border.all(color: DashboardTheme.divider),
                ),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Installed Version',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: s(14),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: s(4)),
                        Text(
                          _appVersion.isNotEmpty
                              ? 'v$_appVersion+$_buildNumber'
                              : 'Loading...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: s(22),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(width: s(64)),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Environment',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: s(14),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: s(4)),
                        Text(
                          environment.toUpperCase(),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: s(22),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              SizedBox(height: s(32)),

              // Beta Key Input Field
              Text(
                'BETA ACCESS KEY',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: s(14),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              SizedBox(height: s(12)),
              Container(
                decoration: BoxDecoration(
                  color: DashboardTheme.surface,
                  borderRadius: BorderRadius.circular(s(12)),
                  border: Border.all(color: DashboardTheme.divider),
                ),
                child: TextField(
                  controller: _keyController,
                  focusNode: _inputFocusNode,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: s(18),
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    hintText: 'Paste or enter beta access key',
                    hintStyle: TextStyle(
                      color: Colors.white30,
                      fontSize: s(16),
                      fontFamily: 'monospace',
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: s(20),
                      vertical: s(16),
                    ),
                    border: InputBorder.none,
                  ),
                ),
              ),

              SizedBox(height: s(24)),

              // Action Buttons Row
              Row(
                children: [
                  // Activate Beta Button
                  LongPressFocus(
                    focusNode: _activateFocusNode,
                    onTap: _isLoading ? () {} : _activateBetaChannel,
                    child: Builder(builder: (context) {
                      final focused = Focus.of(context).hasFocus;
                      return Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: s(28),
                          vertical: s(16),
                        ),
                        decoration: BoxDecoration(
                          color: focused
                              ? Colors.white
                              : DashboardTheme.warningAmber
                                  .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(s(12)),
                          border: Border.all(
                            color: focused
                                ? Colors.white
                                : DashboardTheme.warningAmber
                                    .withValues(alpha: 0.5),
                            width: s(1.5),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.key_rounded,
                              size: s(20),
                              color: focused
                                  ? Colors.black
                                  : DashboardTheme.warningAmber,
                            ),
                            SizedBox(width: s(12)),
                            Text(
                              'Activate Key',
                              style: TextStyle(
                                color: focused
                                    ? Colors.black
                                    : DashboardTheme.warningAmber,
                                fontSize: s(18),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),

                  SizedBox(width: s(20)),

                  // Check for Channel Updates Button
                  LongPressFocus(
                    focusNode: _checkUpdateFocusNode,
                    onTap: _isLoading ? () {} : _checkForChannelUpdate,
                    child: Builder(builder: (context) {
                      final focused = Focus.of(context).hasFocus;
                      return Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: s(28),
                          vertical: s(16),
                        ),
                        decoration: BoxDecoration(
                          color: focused
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(s(12)),
                          border: Border.all(
                            color: focused ? Colors.white : Colors.white24,
                            width: s(1.5),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.refresh_rounded,
                              size: s(20),
                              color: focused ? Colors.black : Colors.white,
                            ),
                            SizedBox(width: s(12)),
                            Text(
                              'Check Updates',
                              style: TextStyle(
                                color: focused ? Colors.black : Colors.white,
                                fontSize: s(18),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),

                  if (!isStable) ...[
                    SizedBox(width: s(20)),
                    // Reset to Stable Button
                    LongPressFocus(
                      focusNode: _clearBetaFocusNode,
                      onTap: _isLoading ? () {} : _resetToStable,
                      child: Builder(builder: (context) {
                        final focused = Focus.of(context).hasFocus;
                        return Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: s(24),
                            vertical: s(16),
                          ),
                          decoration: BoxDecoration(
                            color: focused
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(s(12)),
                            border: Border.all(
                              color: focused ? Colors.white : Colors.white12,
                              width: s(1.5),
                            ),
                          ),
                          child: Text(
                            'Leave Beta',
                            style: TextStyle(
                              color: focused ? Colors.black : Colors.white60,
                              fontSize: s(18),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ],
              ),

              if (_statusMessage != null) ...[
                SizedBox(height: s(24)),
                // Status Feedback Banner
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: s(20),
                    vertical: s(12),
                  ),
                  decoration: BoxDecoration(
                    color: _isSuccessMessage
                        ? DashboardTheme.successGreen.withValues(alpha: 0.15)
                        : Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(s(8)),
                    border: Border.all(
                      color: _isSuccessMessage
                          ? DashboardTheme.successGreen.withValues(alpha: 0.5)
                          : Colors.red.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isSuccessMessage
                            ? Icons.check_circle_rounded
                            : Icons.error_outline_rounded,
                        color: _isSuccessMessage
                            ? DashboardTheme.successGreen
                            : Colors.redAccent,
                        size: s(20),
                      ),
                      SizedBox(width: s(12)),
                      Text(
                        _statusMessage!,
                        style: TextStyle(
                          color: _isSuccessMessage
                              ? DashboardTheme.successGreen
                              : Colors.redAccent,
                          fontSize: s(16),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
