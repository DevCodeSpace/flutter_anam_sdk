import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class AnamAvatarView extends StatefulWidget {
  final RTCVideoRenderer? renderer;
  final bool showControls;
  final VoidCallback? onMicToggle;
  final bool isMicEnabled;
  final double borderRadius;
  final Color backgroundColor;

  const AnamAvatarView({
    super.key,
    required this.renderer,
    this.showControls = true,
    this.onMicToggle,
    this.isMicEnabled = true,
    this.borderRadius = 12.0,
    this.backgroundColor = Colors.black,
  });

  @override
  State<AnamAvatarView> createState() => _AnamAvatarViewState();
}

class _AnamAvatarViewState extends State<AnamAvatarView> {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: widget.backgroundColor,
        borderRadius: BorderRadius.circular(widget.borderRadius),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.renderer != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              child: RepaintBoundary(
                child: RTCVideoView(
                  widget.renderer!,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                  mirror: false,
                  filterQuality: FilterQuality.low,
                ),
              ),
            )
          else
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.person_outline,
                    size: 80,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Waiting for avatar...',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          if (widget.showControls && widget.onMicToggle != null)
            Positioned(
              bottom: 16,
              right: 16,
              child: FloatingActionButton(
                mini: true,
                backgroundColor: widget.isMicEnabled
                    ? Theme.of(context).primaryColor
                    : Colors.red,
                onPressed: widget.onMicToggle,
                child: Icon(
                  widget.isMicEnabled ? Icons.mic : Icons.mic_off,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
