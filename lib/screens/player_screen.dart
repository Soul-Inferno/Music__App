import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:file_picker/file_picker.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late AudioPlayer _audioPlayer;
  final List<AudioFile> _playlist = [];
  int _currentIndex = -1;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  double _volume = 1.0;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _setupAudioPlayer();
  }

  void _setupAudioPlayer() {
    _audioPlayer.durationStream.listen((duration) {
      setState(() => _duration = duration ?? Duration.zero);
    });

    _audioPlayer.positionStream.listen((position) {
      setState(() => _position = position);
    });

    _audioPlayer.playerStateStream.listen((state) {
      setState(() => _isPlaying = state.playing);
      if (state.processingState == ProcessingState.completed) {
        _playNext();
      }
    });
  }

  Future<void> _pickAudioFiles() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.audio,
      );

      if (result != null) {
        setState(() {
          _playlist.addAll(
            result.files.map((file) => AudioFile(
              path: file.path ?? '',
              name: file.name,
            )),
          );
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking files: $e')),
      );
    }
  }

  Future<void> _playAudio(int index) async {
    if (index >= _playlist.length) return;

    try {
      await _audioPlayer.setFilePath(_playlist[index].path);
      await _audioPlayer.play();
      setState(() => _currentIndex = index);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error playing audio: $e')),
      );
    }
  }

  void _playNext() {
    if (_currentIndex < _playlist.length - 1) {
      _playAudio(_currentIndex + 1);
    }
  }

  void _playPrevious() {
    if (_currentIndex > 0) {
      _playAudio(_currentIndex - 1);
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Music Player'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Now Playing Section
          Expanded(
            child: Container(
              color: Colors.grey.shade100,
              child: Center(
                child: _currentIndex >= 0
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.music_note,
                            size: 120,
                            color: Colors.blue,
                          ),
                          const SizedBox(height: 24),
                          Text(
                            _playlist[_currentIndex].name,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                minHeight: 6,
                                value: _duration.inMilliseconds > 0
                                    ? _position.inMilliseconds /
                                        _duration.inMilliseconds
                                    : 0,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _formatDuration(_position),
                                  style: const TextStyle(fontSize: 12),
                                ),
                                Text(
                                  _formatDuration(_duration),
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.music_note,
                            size: 80,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No song playing',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),

          // Control Section
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // Volume Control
                Row(
                  children: [
                    const Icon(Icons.volume_down),
                    Expanded(
                      child: Slider(
                        value: _volume,
                        onChanged: (value) {
                          setState(() => _volume = value);
                          _audioPlayer.setVolume(value);
                        },
                      ),
                    ),
                    const Icon(Icons.volume_up),
                  ],
                ),
                const SizedBox(height: 24),

                // Playback Controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.skip_previous),
                      onPressed: _currentIndex > 0 ? _playPrevious : null,
                      iconSize: 32,
                    ),
                    const SizedBox(width: 16),
                    FloatingActionButton(
                      onPressed: () async {
                        if (_isPlaying) {
                          await _audioPlayer.pause();
                        } else if (_currentIndex >= 0) {
                          await _audioPlayer.play();
                        }
                      },
                      child: Icon(
                        _isPlaying ? Icons.pause : Icons.play_arrow,
                      ),
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: const Icon(Icons.stop),
                      onPressed: _currentIndex >= 0
                          ? () async => await _audioPlayer.stop()
                          : null,
                      iconSize: 32,
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: const Icon(Icons.skip_next),
                      onPressed: _currentIndex < _playlist.length - 1
                          ? _playNext
                          : null,
                      iconSize: 32,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Playlist Section
          Expanded(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Playlist (${_playlist.length})',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _pickAudioFiles,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Songs'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _playlist.isEmpty
                      ? const Center(
                          child: Text('No songs in playlist'),
                        )
                      : ListView.builder(
                          itemCount: _playlist.length,
                          itemBuilder: (context, index) {
                            final isCurrentPlaying = index == _currentIndex;
                            return ListTile(
                              selected: isCurrentPlaying,
                              selectedTileColor: Colors.blue.shade100,
                              title: Text(_playlist[index].name),
                              leading: Text('${index + 1}'),
                              trailing: IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  setState(() {
                                    _playlist.removeAt(index);
                                    if (index == _currentIndex) {
                                      _audioPlayer.stop();
                                      _currentIndex = -1;
                                    }
                                  });
                                },
                              ),
                              onTap: () => _playAudio(index),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AudioFile {
  final String path;
  final String name;

  AudioFile({
    required this.path,
    required this.name,
  });
}
