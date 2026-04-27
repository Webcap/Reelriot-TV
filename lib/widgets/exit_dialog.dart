import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reelriot_tv/utils/tv_keys.dart';

class ExitDialog extends StatelessWidget {
  const ExitDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 600,
        padding: const EdgeInsets.all(48),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white12, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon / Header
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFEC1D24).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.logout_rounded,
                color: Color(0xFFEC1D24),
                size: 64,
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'EXIT REELRIOT?',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Are you sure you want to quit the application? We\'ll miss you!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 20,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 48),
            Row(
              children: [
                Expanded(
                  child: _DialogButton(
                    label: 'CANCEL',
                    onTap: () => Navigator.of(context).pop(false),
                    isPrimary: false,
                    autofocus: true,
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: _DialogButton(
                    label: 'EXIT',
                    onTap: () => Navigator.of(context).pop(true),
                    isPrimary: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool isPrimary;
  final bool autofocus;

  const _DialogButton({
    required this.label,
    required this.onTap,
    this.isPrimary = false,
    this.autofocus = false,
  });

  @override
  State<_DialogButton> createState() => _DialogButtonState();
}

class _DialogButtonState extends State<_DialogButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && TvKeys.isSelect(event.logicalKey)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: _isFocused
                ? (widget.isPrimary ? const Color(0xFFEC1D24) : Colors.white)
                : (widget.isPrimary ? const Color(0xFFEC1D24).withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isFocused ? Colors.transparent : Colors.white10,
              width: 2,
            ),
          ),
          child: Center(
            child: Text(
              widget.label,
              style: TextStyle(
                color: _isFocused 
                    ? (widget.isPrimary ? Colors.white : Colors.black)
                    : (widget.isPrimary ? const Color(0xFFEC1D24) : Colors.white60),
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
