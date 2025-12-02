import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

class AudioFile {
  final String path;
  final String name;
  final Uint8List? artwork; // reserved for future cover art

  AudioFile({
    required this.path,
    required this.name,
    this.artwork,
  });
}

class Playlist {
  final String name;
  final List<AudioFile> tracks;

  Playlist({required this.name, required this.tracks});
}

class PlayerScreen extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final bool isDark;

  const PlayerScreen({
    super.key,
    required this.onToggleTheme,
    required this.isDark,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late AudioPlayer _audioPlayer;
  final List<AudioFile> _songs = [];
  final List<AudioFile> _liked = [];
  final List<Playlist> _playlists = [];

  int _currentIndex = -1;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  double _volume = 1.0;
  bool _isShuffle = false;
  LoopMode _loopMode = LoopMode.off;

  int _bottomIndex = 0; // 0 = Home, 1 = Library

  @override
  void initState() {
    super.initState();
    _setupAudioPlayer();
  }

  void _setupAudioPlayer() {
    _audioPlayer = AudioPlayer();
    _audioPlayer.setSpeed(1.0); // always 1x [web:2][web:285]

    _audioPlayer.durationStream.listen((d) {
      setState(() => _duration = d ?? Duration.zero);
    });

    _audioPlayer.positionStream.listen((p) {
      setState(() => _position = p);
    });

    _audioPlayer.playerStateStream.listen((s) {
      setState(() => _isPlaying = s.playing);
      if (s.processingState == ProcessingState.completed) {
        _handleComplete();
      }
    });
  }

  void _handleComplete() {
    if (_loopMode == LoopMode.one) {
      _playAudio(_currentIndex);
    } else if (_isShuffle) {
      _playAudio(_getRandomIndex());
    } else if (_loopMode == LoopMode.all &&
        _songs.isNotEmpty &&
        _currentIndex == _songs.length - 1) {
      _playAudio(0);
    } else {
      _playNext();
    }
  }

  int _getRandomIndex() {
    if (_songs.isEmpty) return -1;
    final list = List<int>.generate(_songs.length, (i) => i)
      ..remove(_currentIndex);
    list.shuffle();
    return list.isEmpty ? _currentIndex : list.first;
  }

  Future<void> _pickAudioFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'aac', 'm4a', 'flac'],
        withData: false,
      );

      if (result == null) return;

      final List<AudioFile> newItems = [];

      for (final f in result.files) {
        if (f.path == null || f.path!.isEmpty) {
          debugPrint(
            '[FilePicker] Skipping "${f.name}" – no filesystem path (unknown_path)',
          );
          _showSnack('Could not load "${f.name}" from this location.');
          continue;
        }

        newItems.add(
          AudioFile(
            path: f.path!,
            name: f.name,
            artwork: null,
          ),
        );
      }

      if (newItems.isEmpty) return;

      setState(() {
        _songs.addAll(newItems);
      });
    } catch (e) {
      _showSnack('Error picking files: $e');
    }
  }

  Future<void> _playAudio(int index) async {
    if (index < 0 || index >= _songs.length) return;

    // make mini-player appear immediately
    setState(() {
      _currentIndex = index;
    });

    try {
      await _audioPlayer.setFilePath(_songs[index].path);
      await _audioPlayer.play();
    } catch (e) {
      _showSnack('Error playing audio: $e');
      setState(() => _currentIndex = -1);
    }
  }

  void _playNext() {
    if (_isShuffle) {
      _playAudio(_getRandomIndex());
    } else if (_currentIndex < _songs.length - 1) {
      _playAudio(_currentIndex + 1);
    } else if (_loopMode == LoopMode.all) {
      _playAudio(0);
    }
  }

  void _playPrevious() {
    if (_currentIndex > 0) {
      _playAudio(_currentIndex - 1);
    }
  }

  void _toggleShuffle() {
    setState(() => _isShuffle = !_isShuffle);
  }

  void _toggleLoop() {
    setState(() {
      if (_loopMode == LoopMode.off) {
        _loopMode = LoopMode.all;
      } else if (_loopMode == LoopMode.all) {
        _loopMode = LoopMode.one;
      } else {
        _loopMode = LoopMode.off;
      }
      _audioPlayer.setLoopMode(_loopMode);
    });
  }

  bool _isLiked(AudioFile f) =>
      _liked.any((x) => x.path == f.path);

  void _toggleLike(AudioFile f) {
    setState(() {
      if (_isLiked(f)) {
        _liked.removeWhere((x) => x.path == f.path);
      } else {
        _liked.add(f);
      }
    });
  }

  String _format(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Widget _placeholderArtwork(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.grey.shade800,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(
        Icons.music_note,
        size: 48,
        color: Colors.white70,
      ),
    );
  }

  // ---------------- MAIN BUILD ----------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Music Player'),
        actions: [
          IconButton(
            icon: Icon(widget.isDark ? Icons.light_mode : Icons.dark_mode),
            onPressed: widget.onToggleTheme,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (_bottomIndex == 0) {
            _pickAudioFiles();
          } else {
            _showCreatePlaylistDialog();
          }
        },
        icon: Icon(_bottomIndex == 0 ? Icons.add : Icons.playlist_add),
        label: Text(_bottomIndex == 0 ? 'Add Songs' : 'New Playlist'),
      ),
      body: IndexedStack(
        index: _bottomIndex,
        children: [
          _buildPlayerView(context, cs),   // Home
          _buildLibraryRoot(context),      // Library
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _bottomIndex,
        onDestinationSelected: (i) {
          setState(() => _bottomIndex = i);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music),
            label: 'Library',
          ),
        ],
      ),
    );
  }

  // ---------------- HOME / MINI PLAYER VIEW ----------------

  Widget _buildPlayerView(BuildContext context, ColorScheme cs) {
    if (_songs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.music_note, size: 96),
            const SizedBox(height: 16),
            const Text('No songs added'),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _pickAudioFiles,
              icon: const Icon(Icons.add),
              label: const Text('Add Songs'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(child: _buildSongsList()),
        if (_currentIndex != -1) _buildMiniPlayer(context, cs),
      ],
    );
  }

  Widget _buildMiniPlayer(BuildContext context, ColorScheme cs) {
    final current = _songs[_currentIndex];

    return InkWell(
      onTap: () => _openFullPlayerSheet(context, cs),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Container(
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _placeholderArtwork(44),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                current.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
              onPressed: () async {
                if (_isPlaying) {
                  await _audioPlayer.pause();
                } else {
                  await _audioPlayer.play();
                }
              },
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'add_to_playlist') {
                  _showAddToPlaylistDialog(current);
                }
              },
              itemBuilder: (ctx) => const [
                PopupMenuItem(
                  value: 'add_to_playlist',
                  child: Text('Add to playlist'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- FULL PLAYER BOTTOM SHEET ----------------

  void _openFullPlayerSheet(BuildContext context, ColorScheme cs) {
    if (_currentIndex == -1) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          key: ValueKey(_currentIndex),
          initialChildSize: 0.9,
          minChildSize: 0.6,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: _buildFullPlayerContent(context, cs, scrollController),
            );
          },
        );
      },
    );
  }

  Widget _buildFullPlayerContent(
    BuildContext context,
    ColorScheme cs,
    ScrollController scrollController,
  ) {
    final current = _songs[_currentIndex];

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(child: _placeholderArtwork(260)),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(
                current.name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              icon: Icon(
                _isLiked(current) ? Icons.favorite : Icons.favorite_border,
              ),
              onPressed: () => _toggleLike(current),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'add_to_playlist') {
                  _showAddToPlaylistDialog(current);
                }
              },
              itemBuilder: (ctx) => const [
                PopupMenuItem(
                  value: 'add_to_playlist',
                  child: Text('Add to playlist'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),

        // real-time position & time using StreamBuilder
        StreamBuilder<Duration>(
          stream: _audioPlayer.positionStream,
          builder: (context, snapshotPos) {
            final pos = snapshotPos.data ?? _position;
            final dur = _duration;

            final maxMs = dur.inMilliseconds == 0 ? 1 : dur.inMilliseconds;
            final valueMs = pos.inMilliseconds.clamp(0, maxMs);

            return Column(
              children: [
                Slider(
                  value: valueMs.toDouble(),
                  max: maxMs.toDouble(),
                  activeColor: cs.primary,
                  onChanged: (v) =>
                      _audioPlayer.seek(Duration(milliseconds: v.toInt())),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_format(pos)),
                    Text(_format(dur)),
                  ],
                ),
              ],
            );
          },
        ),

        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: Icon(
                Icons.shuffle,
                color: _isShuffle ? cs.primary : Colors.grey,
              ),
              onPressed: _toggleShuffle,
            ),
            IconButton(
              icon: const Icon(Icons.skip_previous),
              iconSize: 32,
              onPressed: _playPrevious,
            ),
            const SizedBox(width: 8),
            FloatingActionButton(
              heroTag: 'full_play_pause',
              onPressed: () async {
                if (_isPlaying) {
                  await _audioPlayer.pause();
                } else {
                  await _audioPlayer.play();
                }
              },
              child: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.skip_next),
              iconSize: 32,
              onPressed: _playNext,
            ),
            IconButton(
              icon: Icon(
                _loopMode == LoopMode.one ? Icons.repeat_one : Icons.repeat,
                color: _loopMode == LoopMode.off ? Colors.grey : cs.primary,
              ),
              onPressed: _toggleLoop,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.volume_down),
            Expanded(
              child: Slider(
                value: _volume,
                activeColor: cs.primary,
                onChanged: (v) {
                  setState(() => _volume = v);
                  _audioPlayer.setVolume(v);
                },
              ),
            ),
            const Icon(Icons.volume_up),
          ],
        ),
      ],
    );
  }

  Widget _buildSongsList() {
    return ListView.builder(
      itemCount: _songs.length,
      itemBuilder: (context, i) {
        final song = _songs[i];
        final isCurrent = i == _currentIndex;
        return ListTile(
          leading: _placeholderArtwork(42),
          title: Text(song.name),
          selected: isCurrent,
          selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
          onTap: () => _playAudio(i),
          trailing: PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'add_to_playlist') {
                _showAddToPlaylistDialog(song);
              } else if (value == 'remove') {
                setState(() {
                  if (i == _currentIndex) {
                    _audioPlayer.stop();
                    _currentIndex = -1;
                  }
                  _songs.removeAt(i);
                });
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: 'add_to_playlist',
                child: Text('Add to playlist'),
              ),
              PopupMenuItem(
                value: 'remove',
                child: Text('Remove from library'),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------- LIBRARY: PLAYLISTS + LIKED ----------------

  Widget _buildLibraryRoot(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Your Library'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Playlists', icon: Icon(Icons.queue_music)),
              Tab(text: 'Liked Songs', icon: Icon(Icons.favorite)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildPlaylistsTab(context),
            _buildLikedTab(context),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistsTab(BuildContext context) {
    if (_playlists.isEmpty) {
      return const Center(
        child: Text('No playlists yet. Use "New Playlist" to create one.'),
      );
    }
    return ListView.builder(
      itemCount: _playlists.length,
      itemBuilder: (context, index) {
        final pl = _playlists[index];
        return ListTile(
          leading: const Icon(Icons.queue_music),
          title: Text(pl.name),
          subtitle: Text('${pl.tracks.length} songs'),
          onTap: () => _openPlaylist(pl),
        );
      },
    );
  }

  Widget _buildLikedTab(BuildContext context) {
    if (_liked.isEmpty) {
      return const Center(child: Text('No liked songs yet.'));
    }
    return ListView.builder(
      itemCount: _liked.length,
      itemBuilder: (context, index) {
        final song = _liked[index];
        return ListTile(
          leading: _placeholderArtwork(42),
          title: Text(song.name),
          onTap: () {
            final idx = _songs.indexWhere((s) => s.path == song.path);
            if (idx != -1) {
              _playAudio(idx);
              setState(() => _bottomIndex = 0);
            }
          },
        );
      },
    );
  }

  void _showCreatePlaylistDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Playlist'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Playlist name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                setState(() {
                  _playlists.add(Playlist(name: name, tracks: []));
                });
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showAddToPlaylistDialog(AudioFile song) {
    if (_playlists.isEmpty) {
      _showSnack('No playlists yet. Create one first.');
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Add to playlist'),
        children: _playlists.map((pl) {
          return SimpleDialogOption(
            onPressed: () {
              setState(() {
                if (!pl.tracks.any((t) => t.path == song.path)) {
                  pl.tracks.add(song);
                }
              });
              Navigator.of(ctx).pop();
              _showSnack('Added to "${pl.name}"');
            },
            child: Text(pl.name),
          );
        }).toList(),
      ),
    );
  }

  void _openPlaylist(Playlist pl) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          builder: (ctx, scrollController) {
            return Column(
              children: [
                ListTile(
                  title: Text(
                    pl.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  child: pl.tracks.isEmpty
                      ? const Center(child: Text('No songs in this playlist'))
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: pl.tracks.length,
                          itemBuilder: (context, i) {
                            final song = pl.tracks[i];
                            return ListTile(
                              leading: _placeholderArtwork(42),
                              title: Text(song.name),
                              onTap: () {
                                final idx = _songs.indexWhere(
                                    (s) => s.path == song.path);
                                if (idx != -1) {
                                  Navigator.of(ctx).pop();
                                  _playAudio(idx);
                                  setState(() => _bottomIndex = 0);
                                }
                              },
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
