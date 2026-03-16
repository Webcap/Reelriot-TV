import 'package:better_player/better_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PlayerSettingsOverlay extends StatefulWidget {
  final BetterPlayerController controller;

  const PlayerSettingsOverlay({super.key, required this.controller});

  @override
  State<PlayerSettingsOverlay> createState() => _PlayerSettingsOverlayState();
}

class _PlayerSettingsOverlayState extends State<PlayerSettingsOverlay> {
  @override
  Widget build(BuildContext context) {
    final audioTracks = widget.controller.betterPlayerAsmsAudioTracks ?? [];
    final subtitleSources = widget.controller.betterPlayerSubtitlesSourceList;
    final currentAudio = widget.controller.betterPlayerAsmsAudioTrack;
    final currentSubtitle = widget.controller.betterPlayerSubtitlesSource;

    return Center(
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white24, width: 2),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Player Options',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 32),
              if (audioTracks.isNotEmpty) ...[
                const _CategoryHeader(title: 'Audio Language'),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: audioTracks.map((track) {
                    final isSelected = currentAudio == track;
                    return _TrackChip(
                      label: track.label ?? track.language ?? 'Unknown',
                      isSelected: isSelected,
                      onPressed: () {
                        widget.controller.setAudioTrack(track);
                        setState(() {});
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 32),
              ],
              if (subtitleSources.isNotEmpty) ...[
                const _CategoryHeader(title: 'Subtitles'),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: subtitleSources.map((source) {
                    final isSelected = currentSubtitle == source;
                    final name = source.name ?? 'Unknown';
                    return _TrackChip(
                      label: name == 'Default subtitles' && source.type == BetterPlayerSubtitlesSourceType.none 
                          ? 'Off' 
                          : name,
                      isSelected: isSelected,
                      onPressed: () {
                        widget.controller.setupSubtitleSource(source);
                        setState(() {});
                      },
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 48),
              Center(
                child: _TrackChip(
                  label: 'Close',
                  isSelected: false,
                  isAction: true,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  final String title;
  const _CategoryHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 14,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _TrackChip extends StatefulWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onPressed;
  final bool isAction;

  const _TrackChip({
    required this.label,
    required this.isSelected,
    required this.onPressed,
    this.isAction = false,
  });

  @override
  State<_TrackChip> createState() => _TrackChipState();
}

class _TrackChipState extends State<_TrackChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isSelected 
        ? const Color(0xFFDC2626) 
        : (_focused ? Colors.white : Colors.white10);
    
    final textColor = widget.isSelected 
        ? Colors.white 
        : (_focused ? Colors.black : Colors.white70);

    return Focus(
      onFocusChange: (hasFocus) => setState(() => _focused = hasFocus),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.select)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: _focused ? Border.all(color: Colors.white, width: 2) : null,
            boxShadow: _focused ? [
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.3),
                blurRadius: 12,
                spreadRadius: 2,
              )
            ] : null,
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: textColor,
              fontWeight: widget.isSelected || _focused ? FontWeight.bold : FontWeight.normal,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }
}
