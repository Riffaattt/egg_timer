import 'package:flutter/material.dart';
import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // ← penting untuk async
  runApp(const EggTimerApp());
}

class EggTimerApp extends StatefulWidget {
  const EggTimerApp({super.key});

  @override
  State<EggTimerApp> createState() => _EggTimerAppState();
}

class _EggTimerAppState extends State<EggTimerApp> {
  late Future<ThemeMode> _themeModeFuture;

  @override
  void initState() {
    super.initState();
    _themeModeFuture = _loadThemeMode();
  }

  Future<ThemeMode> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('theme_mode') ?? 'system';
    switch (saved) {
      case 'light': return ThemeMode.light;
      case 'dark': return ThemeMode.dark;
      default: return ThemeMode.system;
    }
  }

  Future<void> _saveThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    String value;
    switch (mode) {
      case ThemeMode.light: value = 'light'; break;
      case ThemeMode.dark: value = 'dark'; break;
      default: value = 'system';
    }
    prefs.setString('theme_mode', value);
    // Refresh UI
    setState(() {
      _themeModeFuture = Future.value(mode);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ThemeMode>(
      future: _themeModeFuture,
      builder: (context, snapshot) {
        final themeMode = snapshot.data ?? ThemeMode.system;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Egg Master',
          theme: ThemeData.light(useMaterial3: true),
          darkTheme: ThemeData.dark(useMaterial3: true),
          themeMode: themeMode,
          home: HomePage(
            onThemeChanged: (mode) => _saveThemeMode(mode),
          ),
        );
      },
    );
  }
}

// Ubah HomePage jadi non-const dan terima callback
class HomePage extends StatefulWidget {
  final ValueChanged<ThemeMode> onThemeChanged;
  const HomePage({super.key, required this.onThemeChanged});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Timer? _timer;
  int _totalSeconds = 0;
  int _remainingSeconds = 0;
  String _selectedDoneness = 'soft';
  String _selectedSize = 'sedang';
  bool _isRunning = false;
  bool _isPaused = false;

  final Map<String, int> _donenessTimes = {
    'warm': 2 * 60,
    'soft': 4 * 60,
    'medium_soft': 5 * 60,
    'medium': 6 * 60,
    'medium_hard': 7 * 60,
    'hard': 8 * 60 + 30,
    'overcooked': 11 * 60,
  };

  final Map<String, String> _donenessLabels = {
    'warm': 'Telur Hangat',
    'soft': 'Telur Setengah Matang',
    'medium_soft': 'Telur Medium-Soft',
    'medium': 'Telur Sedang',
    'medium_hard': 'Telur Medium-Hard',
    'hard': 'Telur Matang Sempurna',
    'overcooked': 'Telur Overcooked (Kering)',
  };

  final Map<String, String> _sizeLabels = {
    'kecil': 'Kecil (40–50g)',
    'sedang': 'Sedang (50–60g)',
    'besar': 'Besar (60–70g)',
    'jumbo': 'Jumbo (>70g)',
  };

  final Map<String, double> _sizeMultiplier = {
    'kecil': 0.85,
    'sedang': 1.0,
    'besar': 1.15,
    'jumbo': 1.30,
  };

  late AudioPlayer _audioPlayer;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _loadLastSettings();
  }

  Future<void> _loadLastSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      final savedDoneness = prefs.getString('last_doneness');
      if (savedDoneness != null && _donenessTimes.containsKey(savedDoneness)) {
        _selectedDoneness = savedDoneness;
      } else {
        _selectedDoneness = 'soft';
      }

      final savedSize = prefs.getString('last_size');
      if (savedSize != null && _sizeMultiplier.containsKey(savedSize)) {
        _selectedSize = savedSize;
      } else {
        _selectedSize = 'sedang';
      }

      _remainingSeconds = _calculateTime();
    });
  }

  int _calculateTime() {
    final baseTime = _donenessTimes[_selectedDoneness] ?? _donenessTimes['soft']!;
    final multiplier = _sizeMultiplier[_selectedSize] ?? 1.0;
    return (baseTime * multiplier).round();
  }

  void _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('last_doneness', _selectedDoneness);
    prefs.setString('last_size', _selectedSize);
  }

  void _startTimer() {
    if (_isRunning && !_isPaused) return;
    if (_isPaused) {
      _isPaused = false;
      _resumeTimer();
      return;
    }

    _totalSeconds = _calculateTime();
    _remainingSeconds = _totalSeconds;
    _isRunning = true;
    _isPaused = false;

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        _timer?.cancel();
        _isRunning = false;
        _playCompletionSound();
        _vibrateDevice();
        _showCompletionSnackbar();
      }
    });
  }

  void _resumeTimer() {
    if (!_isPaused) return;
    _isPaused = false;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        _timer?.cancel();
        _isRunning = false;
        _playCompletionSound();
        _vibrateDevice();
        _showCompletionSnackbar();
      }
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _isRunning = false;
    _isPaused = false;
    _remainingSeconds = 0;
  }

  void _playCompletionSound() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/ding.mp3'));
    } catch (e) {
      debugPrint("Gagal memutar suara: $e");
    }
  }

  void _vibrateDevice() {
    HapticFeedback.lightImpact();
  }

  void _showCompletionSnackbar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Telur ${_donenessLabels[_selectedDoneness]!} sudah siap!'),
        backgroundColor: Colors.green[700],
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Ulang',
          onPressed: () {
            _stopTimer();
            setState(() {
              _remainingSeconds = _calculateTime();
            });
          },
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🍳 Egg Master'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.brightness_6_outlined),
            onPressed: () {
              // Buka dialog pilihan tema
              _showThemeDialog(context);
            },
          ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Riwayat belum tersedia')),
              );
            },
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DropdownButtonFormField<String>(
              value: _selectedDoneness,
              decoration: const InputDecoration(
                labelText: 'Tingkat Kematangan',
                border: OutlineInputBorder(),
              ),
              items: _donenessTimes.keys.map((key) {
                return DropdownMenuItem(
                  value: key,
                  child: Text(_donenessLabels[key]!),
                );
              }).toList(),
              onChanged: _isRunning
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() {
                          _selectedDoneness = value;
                          _remainingSeconds = _calculateTime();
                          _saveSettings();
                        });
                      }
                    },
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              value: _selectedSize,
              decoration: const InputDecoration(
                labelText: 'Ukuran Telur',
                border: OutlineInputBorder(),
              ),
              items: _sizeMultiplier.keys.map((key) {
                return DropdownMenuItem(
                  value: key,
                  child: Text(_sizeLabels[key]!),
                );
              }).toList(),
              onChanged: _isRunning
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() {
                          _selectedSize = value;
                          _remainingSeconds = _calculateTime();
                          _saveSettings();
                        });
                      }
                    },
            ),
            const SizedBox(height: 40),
            Container(
              height: 100,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.grey[100],
              ),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 800),
                      curve: Curves.easeInOut,
                      width: _isRunning ? 10 : 6,
                      height: _isRunning ? 10 : 6,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isRunning
                            ? Colors.orange.withOpacity(0.6)
                            : Colors.grey[400],
                      ),
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(height: 40),
            Text(
              _formatDuration(_remainingSeconds),
              style: const TextStyle(
                fontSize: 72,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _isRunning && !_isPaused
                      ? null
                      : () => _startTimer(),
                  icon: Icon(_isRunning && !_isPaused
                      ? Icons.pause
                      : Icons.play_arrow),
                  label: Text(_isRunning && !_isPaused ? 'Jeda' : 'Mulai'),
                ),
                ElevatedButton.icon(
                  onPressed: _isRunning ? () => _stopTimer() : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                ),
                ElevatedButton.icon(
                  onPressed: _isRunning && _isPaused
                      ? () => _resumeTimer()
                      : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Lanjut'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showThemeDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.brightness_7_outlined),
                title: const Text('Terang'),
                onTap: () {
                  widget.onThemeChanged(ThemeMode.light);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.brightness_4_outlined),
                title: const Text('Gelap'),
                onTap: () {
                  widget.onThemeChanged(ThemeMode.dark);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.device_hub_outlined),
                title: const Text('Ikuti Sistem'),
                onTap: () {
                  widget.onThemeChanged(ThemeMode.system);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}