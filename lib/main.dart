import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:latlong2/latlong.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PulsePlayerApp());
}

class PulsePlayerApp extends StatelessWidget {
  const PulsePlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData(brightness: Brightness.dark);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pulse Player',
      theme: baseTheme.copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1DB954),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0E1116),
        textTheme: GoogleFonts.spaceGroteskTextTheme(baseTheme.textTheme).apply(
          bodyColor: const Color(0xFFE7EEF4),
          displayColor: const Color(0xFFE7EEF4),
        ),
      ),
      home: const PlayerHome(),
    );
  }
}

class PlayerHome extends StatefulWidget {
  const PlayerHome({super.key});

  @override
  State<PlayerHome> createState() => _PlayerHomeState();
}

class _PlayerHomeState extends State<PlayerHome>
    with SingleTickerProviderStateMixin {
  late final AnimationController _revealController;
  late final Animation<double> _fadeIn;
  late final AudioPlayer _player;

  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final List<Track> _queue = [];
  final List<SearchResult> _searchResults = [];
  Track? _nowPlaying;
  bool _isLoading = false;
  String? _currentStreamUrl;
  bool _isSearching = false;
  int _tabIndex = 0;

  static const _proxyBaseUrl = 'http://localhost:3001';

  @override
  void initState() {
    super.initState();
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _fadeIn = CurvedAnimation(
      parent: _revealController,
      curve: Curves.easeOutCubic,
    );
    _player = AudioPlayer();
  }

  @override
  void dispose() {
    _revealController.dispose();
    _urlController.dispose();
    _searchController.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<TrackInfo> _fetchTrackInfo(String url) async {
    final infoUri = Uri.parse('$_proxyBaseUrl/info?url=${Uri.encodeComponent(url)}');
    final response = await http.get(infoUri);
    if (response.statusCode != 200) {
      throw Exception('Proxy indisponible.');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return TrackInfo(
      title: payload['title'] as String? ?? 'Sans titre',
      artist: payload['artist'] as String? ?? 'Inconnu',
      duration: payload['duration'] as String? ?? '--:--',
    );
  }

  Future<void> _searchVideos(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() => _searchResults.clear());
      return;
    }
    setState(() => _isSearching = true);
    try {
      final searchUri =
          Uri.parse('$_proxyBaseUrl/search?query=${Uri.encodeComponent(trimmed)}');
      final response = await http.get(searchUri);
      if (response.statusCode != 200) {
        throw Exception('Search failed');
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final results = (payload['results'] as List<dynamic>? ?? [])
          .map((item) => SearchResult(
                title: item['title'] as String? ?? 'Sans titre',
                artist: item['artist'] as String? ?? 'YouTube',
                duration: item['duration'] as String? ?? '--:--',
                url: item['url'] as String? ?? '',
              ))
          .where((item) => item.url.isNotEmpty)
          .toList();
      if (!mounted) return;
      setState(() => _searchResults
        ..clear()
        ..addAll(results));
    } catch (error) {
      _showMessage('Recherche impossible. Lance le proxy.');
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  Future<void> _playFromUrl(String rawUrl) async {
    final url = rawUrl.trim();
    if (url.isEmpty) {
      _showMessage('Colle un lien YouTube valide.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final info = await _fetchTrackInfo(url);
      final streamUrl = '$_proxyBaseUrl/stream?url=${Uri.encodeComponent(url)}';
      _currentStreamUrl = streamUrl;
      await _player.setAudioSource(AudioSource.uri(Uri.parse(streamUrl)));
      await _player.play();
      if (!mounted) return;
      setState(() {
        _nowPlaying = Track(
          title: info.title,
          artist: info.artist,
          duration: info.duration,
          url: url,
        );
        _addToQueueIfMissing(_nowPlaying!);
      });
    } catch (error) {
      _showMessage('Impossible de lire ce lien. Lance le proxy.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _addToQueueIfMissing(Track track) {
    final exists = _queue.any((item) => item.url == track.url);
    if (!exists) {
      _queue.insert(0, track);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FadeTransition(
        opacity: _fadeIn,
        child: Stack(
          children: [
            const _AmbientBackground(),
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _HeaderRow(
                      onBellTap: () {},
                      onSearchTap: () => setState(() => _tabIndex = 1),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: IndexedStack(
                      index: _tabIndex,
                      children: [
                        _HomeTab(
                          nowPlaying: _nowPlaying,
                          queue: _queue,
                          urlController: _urlController,
                          isLoading: _isLoading,
                          player: _player,
                          hasStream: _currentStreamUrl != null,
                          onSubmitUrl: () => _playFromUrl(_urlController.text),
                          onQueueTap: (track) => _playFromUrl(track.url),
                        ),
                        _SearchTab(
                          controller: _searchController,
                          isSearching: _isSearching,
                          results: _searchResults,
                          onSearch: _searchVideos,
                          onResultTap: (result) {
                            _urlController.text = result.url;
                            _playFromUrl(result.url);
                          },
                        ),
                        _QueueTab(
                          queue: _queue,
                          nowPlaying: _nowPlaying,
                          onTap: (track) => _playFromUrl(track.url),
                        ),
                        _ProfileTab(
                          nowPlaying: _nowPlaying,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _PlaybackBar(
                      player: _player,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _BottomNav(
                      currentIndex: _tabIndex,
                      onTap: (index) => setState(() => _tabIndex = index),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({
    required this.nowPlaying,
    required this.queue,
    required this.urlController,
    required this.isLoading,
    required this.player,
    required this.hasStream,
    required this.onSubmitUrl,
    required this.onQueueTap,
  });

  final Track? nowPlaying;
  final List<Track> queue;
  final TextEditingController urlController;
  final bool isLoading;
  final AudioPlayer player;
  final bool hasStream;
  final VoidCallback onSubmitUrl;
  final ValueChanged<Track> onQueueTap;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        const SizedBox(height: 12),
        Text(
          'Pulse pour toi',
          style: GoogleFonts.playfairDisplay(
            fontSize: 34,
            fontWeight: FontWeight.w600,
            color: const Color(0xFFF6F1EA),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Lecteur audio YouTube (son uniquement)',
          style: TextStyle(
            color: Colors.white.withOpacity(0.72),
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 18),
        _UrlInput(
          controller: urlController,
          isLoading: isLoading,
          onSubmit: onSubmitUrl,
        ),
        const SizedBox(height: 20),
        StreamBuilder<PlayerState>(
          stream: player.playerStateStream,
          builder: (context, snapshot) {
            final isPlaying = snapshot.data?.playing ?? false;
            return _NowPlayingCard(
              track: nowPlaying,
              isPlaying: isPlaying,
              onPlayToggle: () {
                if (isPlaying) {
                  player.pause();
                } else if (hasStream) {
                  player.play();
                }
              },
            );
          },
        ),
        const SizedBox(height: 22),
        Text(
          'Dans la file',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white.withOpacity(0.85),
          ),
        ),
        const SizedBox(height: 12),
        if (queue.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Ajoute un lien YouTube pour remplir la file.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
              ),
            ),
          )
        else
          ...queue.map(
            (track) => _QueueTile(
              track: track,
              isActive: track.url == nowPlaying?.url,
              onTap: () => onQueueTap(track),
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _SearchTab extends StatelessWidget {
  const _SearchTab({
    required this.controller,
    required this.isSearching,
    required this.results,
    required this.onSearch,
    required this.onResultTap,
  });

  final TextEditingController controller;
  final bool isSearching;
  final List<SearchResult> results;
  final ValueChanged<String> onSearch;
  final ValueChanged<SearchResult> onResultTap;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        const SizedBox(height: 12),
        Text(
          'Recherche',
          style: GoogleFonts.playfairDisplay(
            fontSize: 30,
            fontWeight: FontWeight.w600,
            color: const Color(0xFFF6F1EA),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Row(
            children: [
              const Icon(Icons.search, color: Colors.white70),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Cherche un artiste ou un titre',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                    border: InputBorder.none,
                  ),
                  onSubmitted: onSearch,
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: isSearching ? null : () => onSearch(controller.text),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1DB954),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: isSearching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Go'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (results.isEmpty && !isSearching)
          Text(
            'Tape un mot-clé et lance la recherche.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
            ),
          )
        else
          ...results.map(
            (result) => _SearchResultTile(
              result: result,
              onTap: () => onResultTap(result),
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _QueueTab extends StatelessWidget {
  const _QueueTab({
    required this.queue,
    required this.nowPlaying,
    required this.onTap,
  });

  final List<Track> queue;
  final Track? nowPlaying;
  final ValueChanged<Track> onTap;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        const SizedBox(height: 12),
        Text(
          'Ta file',
          style: GoogleFonts.playfairDisplay(
            fontSize: 30,
            fontWeight: FontWeight.w600,
            color: const Color(0xFFF6F1EA),
          ),
        ),
        const SizedBox(height: 12),
        if (queue.isEmpty)
          Text(
            'Aucune musique pour le moment.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
            ),
          )
        else
          ...queue.map(
            (track) => _QueueTile(
              track: track,
              isActive: track.url == nowPlaying?.url,
              onTap: () => onTap(track),
            ),
          ),
      ],
    );
  }
}

class _ProfileTab extends StatefulWidget {
  const _ProfileTab({required this.nowPlaying});

  final Track? nowPlaying;

  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> {
  static const LatLng _fallbackCenter = LatLng(48.8566, 2.3522);

  StreamSubscription<Position>? _positionSubscription;
  Position? _position;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _errorMessage = 'Localisation désactivée.';
        });
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        setState(() {
          _errorMessage = 'Autorise la localisation pour voir la carte.';
        });
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _errorMessage = 'Localisation bloquée dans les réglages.';
        });
        return;
      }

      final current = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() => _position = current);

      _positionSubscription?.cancel();
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen((value) {
        if (!mounted) return;
        setState(() => _position = value);
      });
    } catch (error) {
      setState(() {
        _errorMessage = 'Impossible de récupérer la localisation.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final center = _position == null
        ? _fallbackCenter
        : LatLng(_position!.latitude, _position!.longitude);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        const SizedBox(height: 12),
        Text(
          'Profil',
          style: GoogleFonts.playfairDisplay(
            fontSize: 30,
            fontWeight: FontWeight.w600,
            color: const Color(0xFFF6F1EA),
          ),
        ),
        const SizedBox(height: 12),
        if (_errorMessage != null)
          Text(
            _errorMessage!,
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
            ),
          ),
        const SizedBox(height: 12),
        Container(
          height: 260,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          clipBehavior: Clip.antiAlias,
          child: FlutterMap(
            options: MapOptions(
              initialCenter: center,
              initialZoom: 15,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.drag |
                    InteractiveFlag.pinchZoom |
                    InteractiveFlag.doubleTapZoom,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'flutter_application_1',
              ),
              if (_position != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: center,
                      width: 44,
                      height: 44,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF1DB954),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.35),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.person_pin_circle,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Row(
            children: [
              const Icon(Icons.music_note, color: Color(0xFF1DB954)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.nowPlaying?.title ?? 'Aucun titre en cours',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.nowPlaying?.artist ?? 'Ajoute un morceau',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                widget.nowPlaying?.duration ?? '--:--',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _UrlInput extends StatelessWidget {
  const _UrlInput({
    required this.controller,
    required this.isLoading,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool isLoading;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          const Icon(Icons.link, color: Colors.white70),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Colle un lien YouTube',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                border: InputBorder.none,
              ),
              onSubmitted: (_) => onSubmit(),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: isLoading ? null : onSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1DB954),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Play'),
          ),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.onBellTap,
    required this.onSearchTap,
  });

  final VoidCallback onBellTap;
  final VoidCallback onSearchTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFFFFB347), Color(0xFFFF6B6B)],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(Icons.headphones, color: Colors.black),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Bonsoir, Hana',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.88),
            ),
          ),
        ),
        IconButton(
          onPressed: onSearchTap,
          icon: const Icon(Icons.search),
          color: Colors.white.withOpacity(0.8),
        ),
        IconButton(
          onPressed: onBellTap,
          icon: const Icon(Icons.notifications_none),
          color: Colors.white.withOpacity(0.8),
        ),
      ],
    );
  }
}

class _NowPlayingCard extends StatelessWidget {
  const _NowPlayingCard({
    required this.track,
    required this.isPlaying,
    required this.onPlayToggle,
  });

  final Track? track;
  final bool isPlaying;
  final VoidCallback onPlayToggle;

  @override
  Widget build(BuildContext context) {
    final title = track?.title ?? 'Aucun morceau';
    final artist = track?.artist ?? 'Ajoute un lien YouTube';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF19212B), Color(0xFF0F131A)],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 24,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                colors: [Color(0xFF1DB954), Color(0xFF0F6B3A)],
              ),
            ),
            child: const Icon(
              Icons.graphic_eq,
              size: 40,
              color: Colors.black,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFF9F6F2),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  artist,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Audio Only',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      track?.duration ?? '--:--',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.55),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            onPressed: onPlayToggle,
            icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
            color: Colors.black,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF1DB954),
              padding: const EdgeInsets.all(12),
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({
    required this.track,
    required this.isActive,
    required this.onTap,
  });

  final Track track;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF1DB954).withOpacity(0.12)
              : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive
                    ? const Color(0xFF1DB954)
                    : const Color(0xFF1DB954).withOpacity(0.6),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isActive ? Colors.white : Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.55),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              track.duration,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.result,
    required this.onTap,
  });

  final SearchResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          children: [
            const Icon(Icons.play_circle_fill, color: Color(0xFF1DB954)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    result.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.55),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              result.duration,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaybackBar extends StatelessWidget {
  const _PlaybackBar({required this.player});

  final AudioPlayer player;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlayerState>(
      stream: player.playerStateStream,
      builder: (context, snapshot) {
        final isPlaying = snapshot.data?.playing ?? false;
        return StreamBuilder<Duration?>(
          stream: player.durationStream,
          builder: (context, durationSnapshot) {
            final duration = durationSnapshot.data ?? Duration.zero;
            return StreamBuilder<Duration>(
              stream: player.positionStream,
              builder: (context, positionSnapshot) {
                final position = positionSnapshot.data ?? Duration.zero;
                final progress = duration.inMilliseconds == 0
                    ? 0.0
                    : position.inMilliseconds / duration.inMilliseconds;
                return Column(
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 12,
                        ),
                        activeTrackColor: const Color(0xFF1DB954),
                        inactiveTrackColor: Colors.white.withOpacity(0.15),
                        thumbColor: const Color(0xFF1DB954),
                      ),
                      child: Slider(
                        value: progress.clamp(0.0, 1.0),
                        onChanged: duration == Duration.zero
                            ? null
                            : (value) {
                                final target = Duration(
                                  milliseconds:
                                      (duration.inMilliseconds * value).round(),
                                );
                                player.seek(target);
                              },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatTime(position),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withOpacity(0.55),
                            ),
                          ),
                          Text(
                            _formatTime(duration),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withOpacity(0.55),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Icon(Icons.shuffle,
                            color: Colors.white.withOpacity(0.6)),
                        Icon(Icons.skip_previous,
                            color: Colors.white.withOpacity(0.8)),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: isPlaying ? 56 : 48,
                          height: isPlaying ? 56 : 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF1DB954),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    const Color(0xFF1DB954).withOpacity(0.5),
                                blurRadius: 16,
                              ),
                            ],
                          ),
                          child: IconButton(
                            onPressed: () {
                              if (isPlaying) {
                                player.pause();
                              } else {
                                player.play();
                              }
                            },
                            icon: Icon(
                              isPlaying ? Icons.pause : Icons.play_arrow,
                              color: Colors.black,
                            ),
                          ),
                        ),
                        Icon(Icons.skip_next,
                            color: Colors.white.withOpacity(0.8)),
                        Icon(Icons.repeat,
                            color: Colors.white.withOpacity(0.6)),
                      ],
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  String _formatTime(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final items = const [
      _NavItem(icon: Icons.home_filled, label: 'Home'),
      _NavItem(icon: Icons.search, label: 'Search'),
      _NavItem(icon: Icons.queue_music, label: 'Queue'),
      _NavItem(icon: Icons.person_outline, label: 'Profil'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(items.length, (index) {
          final item = items[index];
          final isActive = index == currentIndex;
          return Expanded(
            child: InkWell(
              onTap: () => onTap(index),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      item.icon,
                      color: isActive
                          ? const Color(0xFF1DB954)
                          : Colors.white70,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 10,
                        color: isActive
                            ? const Color(0xFF1DB954)
                            : Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class _AmbientBackground extends StatelessWidget {
  const _AmbientBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF11161D), Color(0xFF050607)],
            ),
          ),
        ),
        Positioned(
          top: -140,
          left: -80,
          child: _GlowOrb(
            size: 260,
            color: const Color(0xFF1DB954).withOpacity(0.35),
          ),
        ),
        Positioned(
          bottom: -160,
          right: -60,
          child: _GlowOrb(
            size: 280,
            color: const Color(0xFFFF8A65).withOpacity(0.35),
          ),
        ),
      ],
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withOpacity(0.01)],
        ),
      ),
    );
  }
}

class Track {
  const Track({
    required this.title,
    required this.artist,
    required this.duration,
    required this.url,
  });

  final String title;
  final String artist;
  final String duration;
  final String url;
}

class TrackInfo {
  const TrackInfo({
    required this.title,
    required this.artist,
    required this.duration,
  });

  final String title;
  final String artist;
  final String duration;
}

class SearchResult {
  const SearchResult({
    required this.title,
    required this.artist,
    required this.duration,
    required this.url,
  });

  final String title;
  final String artist;
  final String duration;
  final String url;
}
