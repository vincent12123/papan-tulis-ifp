import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../server/server_client.dart';
import '../ui/theme.dart';

/// Where a catalog video streams from: the school server, with the PIN.
typedef VideoAddress = ({Uri uri, Map<String, String> headers});

/// Resolves a catalog video id to its address (REQ-24).
typedef VideoSource = Future<VideoAddress> Function(String id);

/// Builds the player for one video; tests replace the real one.
typedef VideoPlayerBuilder = Widget Function(VideoAddress address);

/// Video eksperimen (SPEC 1.9, REQ-24): the school's videos that match the
/// circled reaction; one tap plays it here, on the panel.
class VideoDialog extends StatefulWidget {
  const VideoDialog({
    super.key,
    required this.videos,
    required this.source,
    this.player = _realPlayer,
  });

  final List<VideoRef> videos;
  final VideoSource source;
  final VideoPlayerBuilder player;

  static const title = 'Video eksperimen';
  static const close = 'Tutup';
  static const back = 'Daftar video';
  static const loading = 'Membuka video…';
  static const failed =
      'Video tidak bisa diputar. Periksa sambungan ke server sekolah, lalu '
      'coba lagi.';

  static Widget _realPlayer(VideoAddress address) => _Player(address: address);

  @override
  State<VideoDialog> createState() => _VideoDialogState();
}

class _VideoDialogState extends State<VideoDialog> {
  VideoRef? _playing;
  VideoAddress? _address;
  String? _error;

  Future<void> _open(VideoRef video) async {
    setState(() {
      _playing = video;
      _address = null;
      _error = null;
    });
    try {
      final address = await widget.source(video.id);
      if (!mounted || _playing != video) return;
      setState(() => _address = address);
    } on ServerFailure {
      if (mounted) setState(() => _error = VideoDialog.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final playing = _playing;
    final address = _address;
    final Widget body;
    if (playing == null) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final v in widget.videos)
            ListTile(
              minTileHeight: AppSizes.primaryTarget,
              leading: const Icon(Icons.play_circle_outline, size: 40),
              title: Text(v.title, style: theme.textTheme.bodyLarge),
              onTap: () => _open(v),
            ),
        ],
      );
    } else if (_error != null) {
      body = Text(_error!, style: theme.textTheme.bodyLarge);
    } else if (address == null) {
      body = const Row(
        children: [
          CircularProgressIndicator(),
          SizedBox(width: AppSizes.space16),
          Text(VideoDialog.loading),
        ],
      );
    } else {
      body = widget.player(address);
    }
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSizes.space24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200, maxHeight: 900),
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.space24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      playing?.title ?? VideoDialog.title,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  if (playing != null)
                    TextButton.icon(
                      onPressed: () => setState(() => _playing = null),
                      icon: const Icon(Icons.list),
                      label: const Text(VideoDialog.back),
                    ),
                  IconButton(
                    tooltip: VideoDialog.close,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.space16),
              Flexible(child: body),
            ],
          ),
        ),
      ),
    );
  }
}

/// video_player with big controls: play/pause and a position slider.
class _Player extends StatefulWidget {
  const _Player({required this.address});
  final VideoAddress address;

  @override
  State<_Player> createState() => _PlayerState();
}

class _PlayerState extends State<_Player> {
  late final VideoPlayerController _video = VideoPlayerController.networkUrl(
    widget.address.uri,
    httpHeaders: widget.address.headers,
  );
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _video
        .initialize()
        .then((_) {
          if (mounted) setState(() {});
          _video.play();
        })
        .catchError((Object _) {
          if (mounted) setState(() => _failed = true);
        });
    _video.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _video.removeListener(_changed);
    _video.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Text(
        VideoDialog.failed,
        style: Theme.of(context).textTheme.bodyLarge,
      );
    }
    final value = _video.value;
    if (!value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    final total = value.duration.inMilliseconds.toDouble();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: AspectRatio(
            aspectRatio: value.aspectRatio,
            child: VideoPlayer(_video),
          ),
        ),
        Row(
          children: [
            IconButton(
              tooltip: value.isPlaying ? 'Jeda' : 'Putar',
              iconSize: 40,
              onPressed: () => value.isPlaying ? _video.pause() : _video.play(),
              icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
            ),
            Expanded(
              child: Slider(
                value: value.position.inMilliseconds.toDouble().clamp(
                  0,
                  total > 0 ? total : 1,
                ),
                max: total > 0 ? total : 1,
                onChanged: (ms) =>
                    _video.seekTo(Duration(milliseconds: ms.round())),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
