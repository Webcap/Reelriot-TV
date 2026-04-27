import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reelriot_tv/utils/tv_keys.dart';
import 'dart:ui';
import 'package:url_launcher/url_launcher.dart';
import '../services/update_service.dart';

class UpdateScreen extends StatefulWidget {
  final UpdateInfo updateInfo;

  const UpdateScreen({super.key, required this.updateInfo});

  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen> {
  final FocusNode _updateNode = FocusNode();
  final FocusNode _closeNode = FocusNode();

  double s(double v) => (v * MediaQuery.of(context).size.width) / 1920;

  @override
  void dispose() {
    _updateNode.dispose();
    _closeNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background (could be some artistic gradient or blur)
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
                  width: s(1000),
                  padding: EdgeInsets.all(s(60)),
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
                          Icon(Icons.system_update_alt, color: Colors.amber, size: s(48)),
                          SizedBox(width: s(24)),
                          Text(
                            'New Update Available',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: s(42),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: s(40)),
                      Text(
                        'Version ${widget.updateInfo.latestVersion}',
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: s(24),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (widget.updateInfo.changelog != null && widget.updateInfo.changelog!.isNotEmpty) ...[
                        SizedBox(height: s(30)),
                        Text(
                          "What's New:",
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: s(20),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: s(12)),
                        ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: s(300)),
                          child: Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(s(20)),
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(s(12)),
                            ),
                            child: SingleChildScrollView(
                              child: Text(
                                widget.updateInfo.changelog!,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: s(22),
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                      SizedBox(height: s(60)),
                      Row(
                        children: [
                          _UpdateButton(
                            label: 'Update Now',
                            icon: Icons.download,
                            focusNode: _updateNode,
                            autofocus: true,
                            onPressed: _handleUpdate,
                            s: s,
                          ),
                          if (!widget.updateInfo.isForced) ...[
                            SizedBox(width: s(30)),
                            _UpdateButton(
                              label: 'Later',
                              icon: Icons.close,
                              focusNode: _closeNode,
                              isSecondary: true,
                              onPressed: () => Navigator.of(context).pop(),
                              s: s,
                            ),
                          ],
                        ],
                      ),
                      if (widget.updateInfo.isForced) ...[
                        SizedBox(height: s(30)),
                        Text(
                          '* This update is required to continue using the app.',
                          style: TextStyle(
                            color: Colors.redAccent.withValues(alpha: 0.8),
                            fontSize: s(18),
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
    );
  }

  Future<void> _handleUpdate() async {
    if (widget.updateInfo.downloadUrl == null) return;
    final url = Uri.parse(widget.updateInfo.downloadUrl!);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
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
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(horizontal: s(40), vertical: s(24)),
          decoration: BoxDecoration(
            color: _isFocused ? Colors.white : color.withValues(alpha: widget.isSecondary ? 0.2 : 1.0),
            borderRadius: BorderRadius.circular(s(16)),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.3),
                      blurRadius: s(20),
                      spreadRadius: s(5),
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
                size: s(28),
              ),
              SizedBox(width: s(20)),
              Text(
                widget.label,
                style: TextStyle(
                  color: _isFocused ? Colors.black : Colors.white,
                  fontSize: s(24),
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
