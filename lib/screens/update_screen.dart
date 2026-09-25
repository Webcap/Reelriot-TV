import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:reelriot_tv/utils/tv_keys.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/update_service.dart';

enum _DownloadState { idle, downloading, installing, error }

class UpdateScreen extends StatefulWidget {
  final UpdateInfo updateInfo;

  const UpdateScreen({super.key, required this.updateInfo});

  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen> {
  final FocusNode _updateNode = FocusNode();
  final FocusNode _closeNode = FocusNode();
  final FocusNode _changelogNode = FocusNode();
  final ScrollController _changelogController = ScrollController();

  _DownloadState _state = _DownloadState.idle;
  double _downloadProgress = 0.0;
  String? _errorMessage;
  bool _isChangelogFocused = false;

  double s(double v) => (v * MediaQuery.of(context).size.width) / 1920;

  @override
  void initState() {
    super.initState();
    if (widget.updateInfo.isForced) {
      UpdateService().reportTelemetry(
        eventType: 'forced_prompt_shown',
        isForcedPrompt: true,
      );
    }
  }

  @override
  void dispose() {
    _updateNode.dispose();
    _closeNode.dispose();
    _changelogNode.dispose();
    _changelogController.dispose();
    super.dispose();
  }

  Future<void> _handleUpdate() async {
    if (_state == _DownloadState.downloading || _state == _DownloadState.installing) {
      return;
    }

    if (widget.updateInfo.downloadUrl == null || widget.updateInfo.downloadUrl!.isEmpty) {
      setState(() {
        _state = _DownloadState.error;
        _errorMessage = 'Download link is unavailable.';
      });
      return;
    }

    setState(() {
      _state = _DownloadState.downloading;
      _downloadProgress = 0.0;
      _errorMessage = null;
    });

    UpdateService().reportTelemetry(
      eventType: 'update_download_clicked',
      isForcedPrompt: widget.updateInfo.isForced,
    );

    final client = http.Client();
    // Hard timeout: close the connection if the full download takes > 10 minutes.
    // This prevents indefinite hangs on poor TV network conditions.
    Timer? downloadTimeoutTimer;
    bool timedOut = false;
    downloadTimeoutTimer = Timer(const Duration(minutes: 10), () {
      timedOut = true;
      client.close();
      debugPrint('[UpdateScreen] ⏱️ Download timed out after 10 minutes, aborting.');
    });

    try {
      final request = http.Request('GET', Uri.parse(widget.updateInfo.downloadUrl!));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('Server returned HTTP ${response.statusCode}');
      }

      final totalBytes = response.contentLength ?? 0;
      int receivedBytes = 0;

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/update.apk');
      if (await file.exists()) {
        await file.delete();
      }

      final sink = file.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0 && mounted) {
          setState(() {
            _downloadProgress = (receivedBytes / totalBytes).clamp(0.0, 1.0);
          });
        }
      }

      await sink.flush();
      await sink.close();
      downloadTimeoutTimer.cancel();
      client.close();

      if (!mounted) return;

      if (timedOut) {
        setState(() {
          _state = _DownloadState.error;
          _errorMessage = 'Download timed out. Please check your connection.';
        });
        return;
      }

      setState(() {
        _state = _DownloadState.installing;
        _downloadProgress = 1.0;
      });

      // Launch native PackageInstaller via FileProvider MethodChannel
      const installerChannel = MethodChannel('reelriot.tv/package_installer');
      try {
        await installerChannel.invokeMethod('installApk', {'filePath': file.path});
      } on PlatformException catch (pe) {
        debugPrint('[UpdateScreen] Native installer exception: ${pe.message}. Trying fallback.');
        final url = Uri.parse(widget.updateInfo.downloadUrl!);
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        } else {
          throw Exception('Unable to launch installer: ${pe.message}');
        }
      }
    } catch (e) {
      downloadTimeoutTimer.cancel();
      client.close();
      debugPrint('[UpdateScreen] Update error: $e');
      if (mounted) {
        setState(() {
          _state = _DownloadState.error;
          _errorMessage = timedOut
              ? 'Download timed out. Please check your connection.'
              : 'Download failed. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.updateInfo.isForced && _state != _DownloadState.downloading,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Background gradient
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.amber.withValues(alpha: 0.1),
                    Colors.black,
                    Colors.black,
                  ],
                ),
              ),
            ),
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(s(32)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Container(
                    width: s(1040),
                    padding: EdgeInsets.all(s(56)),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(s(32)),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                        width: s(1.5),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.system_update_alt,
                              color: Colors.amber,
                              size: s(48),
                            ),
                            SizedBox(width: s(24)),
                            Text(
                              widget.updateInfo.isForced
                                  ? 'Mandatory Update Required'
                                  : 'New Update Available',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: s(38),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: s(28)),
                        Row(
                          children: [
                            Text(
                              'Version ${widget.updateInfo.latestVersion}',
                              style: TextStyle(
                                color: Colors.amber,
                                fontSize: s(24),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (widget.updateInfo.currentVersion.isNotEmpty) ...[
                              SizedBox(width: s(16)),
                              Text(
                                '(Current: v${widget.updateInfo.currentVersion})',
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: s(18),
                                ),
                              ),
                            ],
                          ],
                        ),

                        // Changelog Section with TV D-Pad Focus & Scroll Support
                        if (widget.updateInfo.changelog != null &&
                            widget.updateInfo.changelog!.isNotEmpty) ...[
                          SizedBox(height: s(24)),
                          Text(
                            "What's New:",
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: s(20),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(height: s(12)),
                          Focus(
                            focusNode: _changelogNode,
                            onFocusChange: (v) => setState(() => _isChangelogFocused = v),
                            onKeyEvent: (node, event) {
                              if (event is KeyDownEvent) {
                                if (TvKeys.isDown(event.logicalKey)) {
                                  _changelogController.animateTo(
                                    _changelogController.offset + s(80),
                                    duration: const Duration(milliseconds: 150),
                                    curve: Curves.easeOut,
                                  );
                                  return KeyEventResult.handled;
                                } else if (TvKeys.isUp(event.logicalKey)) {
                                  _changelogController.animateTo(
                                    (_changelogController.offset - s(80)).clamp(0.0, double.infinity),
                                    duration: const Duration(milliseconds: 150),
                                    curve: Curves.easeOut,
                                  );
                                  return KeyEventResult.handled;
                                }
                              }
                              return KeyEventResult.ignored;
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              constraints: BoxConstraints(maxHeight: s(240)),
                              decoration: BoxDecoration(
                                color: Colors.black38,
                                borderRadius: BorderRadius.circular(s(12)),
                                border: Border.all(
                                  color: _isChangelogFocused ? Colors.amber : Colors.white10,
                                  width: _isChangelogFocused ? s(2) : s(1),
                                ),
                              ),
                              padding: EdgeInsets.all(s(20)),
                              child: SingleChildScrollView(
                                controller: _changelogController,
                                child: Text(
                                  widget.updateInfo.changelog!,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: s(20),
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],

                        SizedBox(height: s(36)),

                        // Downloading Progress View
                        if (_state == _DownloadState.downloading) ...[
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Downloading Update Package...',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: s(20),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '${(_downloadProgress * 100).toStringAsFixed(0)}%',
                                    style: TextStyle(
                                      color: Colors.amber,
                                      fontSize: s(22),
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: s(16)),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(s(8)),
                                child: LinearProgressIndicator(
                                  value: _downloadProgress > 0 ? _downloadProgress : null,
                                  backgroundColor: Colors.white12,
                                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.amber),
                                  minHeight: s(12),
                                ),
                              ),
                            ],
                          ),
                        ] else if (_state == _DownloadState.installing) ...[
                          Row(
                            children: [
                              SizedBox(
                                width: s(28),
                                height: s(28),
                                child: const CircularProgressIndicator(
                                  strokeWidth: 3,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.amber),
                                ),
                              ),
                              SizedBox(width: s(20)),
                              Text(
                                'Launching Package Installer on TV...',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: s(20),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          // Action Buttons View
                          Row(
                            children: [
                              _UpdateButton(
                                label: _state == _DownloadState.error ? 'Retry Update' : 'Update Now',
                                icon: Icons.download_rounded,
                                focusNode: _updateNode,
                                autofocus: true,
                                onPressed: _handleUpdate,
                                s: s,
                              ),
                              if (!widget.updateInfo.isForced) ...[
                                SizedBox(width: s(24)),
                                _UpdateButton(
                                  label: 'Later',
                                  icon: Icons.close_rounded,
                                  focusNode: _closeNode,
                                  isSecondary: true,
                                  onPressed: () => Navigator.of(context).pop(),
                                  s: s,
                                ),
                              ],
                            ],
                          ),
                        ],

                        if (_errorMessage != null) ...[
                          SizedBox(height: s(18)),
                          Text(
                            _errorMessage!,
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontSize: s(18),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],

                        if (widget.updateInfo.isForced) ...[
                          SizedBox(height: s(20)),
                          Text(
                            '* This update is mandatory to continue using ReelRiot TV.',
                            style: TextStyle(
                              color: Colors.redAccent.withValues(alpha: 0.85),
                              fontSize: s(16),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpdateButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final FocusNode focusNode;
  final bool autofocus;
  final bool isSecondary;
  final double Function(double) s;

  const _UpdateButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.focusNode,
    this.autofocus = false,
    this.isSecondary = false,
    required this.s,
  });

  @override
  State<_UpdateButton> createState() => _UpdateButtonState();
}

class _UpdateButtonState extends State<_UpdateButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final color = widget.isSecondary ? Colors.white24 : Colors.amber;

    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (v) => setState(() => _isFocused = v),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && TvKeys.isSelect(event.logicalKey)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(horizontal: s(36), vertical: s(20)),
          decoration: BoxDecoration(
            color: _isFocused
                ? Colors.white
                : color.withValues(alpha: widget.isSecondary ? 0.2 : 1.0),
            borderRadius: BorderRadius.circular(s(16)),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.35),
                      blurRadius: s(24),
                      spreadRadius: s(4),
                    )
                  ]
                : [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                color: _isFocused ? Colors.black : Colors.white,
                size: s(26),
              ),
              SizedBox(width: s(16)),
              Text(
                widget.label,
                style: TextStyle(
                  color: _isFocused ? Colors.black : Colors.white,
                  fontSize: s(22),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
