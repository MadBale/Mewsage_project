import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  HistoryPageState createState() => HistoryPageState();
}

class HistoryPageState extends State<HistoryPage> {
  List<dynamic> historyItems = [];
  bool isLoading = true;
  AudioPlayer audioPlayer = AudioPlayer();
  int? currentlyPlayingIndex;
  bool isPaused = true;
  Set<int> selectedItems = {};
  bool isSelectionMode = false;
  bool isPreparingAudio = false;

  @override
  void initState() {
    super.initState();
    _initAudioPlayer();
    _fetchHistory();
  }

  @override
  void dispose() {
    _stopAudio();
    audioPlayer.dispose();
    super.dispose();
  }

  // ===============================
  // Logic Functions
  // ===============================

  Future<void> _fetchHistory() async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
      selectedItems.clear();
      isSelectionMode = false;
    });

    try {
      final response = await http.get(
        Uri.parse('http://172.20.10.3:8000/api/history'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          historyItems = data.map((item) {
            return {
              'history_id': item['id']?.toString() ?? '',
              'filename': item['filename']?.toString() ?? 'Unknown file',
              'prediction': item['prediction']?.toString() ?? 'Unknown',
              'confidence': item['confidence']?.toDouble() ?? 0.0,
              'timestamp': item['timestamp']?.toString() ?? '',
              'audio_url': item['audio_url']?.toString() ?? '',
            };
          }).toList();
          isLoading = false;
        });
      } else {
        throw Exception('Failed to load history: ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      _showErrorSnackbar('Failed to load history: ${e.toString()}');
    }
  }

  Future<void> _deleteSelectedItems() async {
    if (selectedItems.isEmpty || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('Delete ${selectedItems.length} selected items?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      setState(() => isLoading = true);

      final idsToDelete = selectedItems
          .map((index) => historyItems[index]['history_id'].toString())
          .toList();

      final response = await http.delete(
        Uri.parse('http://172.20.10.3:8000/api/history/delete'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'ids': idsToDelete}),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        await _fetchHistory();
        _showSuccessSnackbar('${idsToDelete.length} items deleted');
      } else {
        throw Exception('Failed to delete items: ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      _showErrorSnackbar('Error: ${e.toString()}');
    }
  }

  Future<void> _initAudioPlayer() async {
    try {
      // Set audio player configuration
      await audioPlayer.setReleaseMode(ReleaseMode.stop);
      await audioPlayer.setVolume(1.0);
      
      // Add debug logging for player state changes
      audioPlayer.onPlayerStateChanged.listen((state) {
        debugPrint('Player state changed: $state');
        if (mounted) {
          setState(() {
            if (state == PlayerState.completed) {
              currentlyPlayingIndex = null;
              isPaused = false;
              isPreparingAudio = false;
            } else if (state == PlayerState.playing) {
              isPaused = false;
              isPreparingAudio = false;
            } else if (state == PlayerState.paused) {
              isPaused = true;
              isPreparingAudio = false;
            }
          });
        }
      });

      audioPlayer.onPositionChanged.listen((position) {
        debugPrint('Position changed: ${position.inSeconds} seconds');
      });

      audioPlayer.onDurationChanged.listen((duration) {
        debugPrint('Duration changed: ${duration.inSeconds} seconds');
      });

      debugPrint('Audio player initialized successfully');
    } catch (e) {
      debugPrint('Error initializing audio player: $e');
    }
  }

  Future<void> _playAudio(String? filename) async {
    if (filename == null || !mounted) return;

    try {
      // If we're already playing this file and it's paused, resume it
      if (currentlyPlayingIndex == historyItems.indexWhere((item) => item['filename'] == filename) && isPaused) {
        debugPrint('Resuming paused audio...');
        setState(() {
          isPreparingAudio = true;
        });
        await audioPlayer.resume();
        setState(() {
          isPaused = false;
          isPreparingAudio = false;
        });
        return;
      }

      setState(() {
        isPreparingAudio = true;
        currentlyPlayingIndex = historyItems.indexWhere((item) => item['filename'] == filename);
      });

      // Always stop and dispose current audio before playing new one
      if (currentlyPlayingIndex != null) {
        debugPrint('Stopping current audio before playing new one...');
        await audioPlayer.stop();
        await audioPlayer.dispose();
        // Create a new instance for the next playback
        audioPlayer = AudioPlayer();
        await _initAudioPlayer();
      }

      // Get just the filename without path if it's included
      final cleanFilename = filename.split('/').last;
      
      // Construct proper URL - only encode the filename part
      final audioUrl = 'http://172.20.10.3:8000/static/audio/${Uri.encodeComponent(cleanFilename)}';
      debugPrint('Attempting to play audio from: $audioUrl');

      // First download the audio file
      final response = await http.get(Uri.parse(audioUrl));
      if (response.statusCode != 200) {
        debugPrint('Failed to download audio file. Status: ${response.statusCode}');
        throw Exception('Failed to download audio file (Status: ${response.statusCode})');
      }

      // Save to temporary file
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/temp_audio.wav');
      await tempFile.writeAsBytes(response.bodyBytes);
      debugPrint('Audio file saved to: ${tempFile.path}');

      // Start playback with error handling
      try {
        debugPrint('Starting audio playback from local file...');
        await audioPlayer.play(DeviceFileSource(tempFile.path));
        debugPrint('Audio playback started successfully');
      } catch (playError) {
        debugPrint('Playback error: $playError');
        throw Exception('Failed to start playback: $playError');
      }

    } catch (e) {
      debugPrint('Audio playback error: $e');
      if (mounted) {
        setState(() {
          currentlyPlayingIndex = null;
          isPaused = false;
          isPreparingAudio = false;
        });
        _showErrorSnackbar('Failed to play audio: ${e.toString()}');
      }
    }
  }

  Future<void> _pauseAudio() async {
    try {
      debugPrint('Pausing audio playback...');
      setState(() {
        isPreparingAudio = true;
      });
      await audioPlayer.pause();
      debugPrint('Audio playback paused successfully');
      if (mounted) {
        setState(() {
          isPaused = true;
          isPreparingAudio = false;
        });
      }
    } catch (e) {
      debugPrint('Error pausing audio: $e');
      if (mounted) {
        setState(() {
          isPreparingAudio = false;
        });
      }
    }
  }

  Future<void> _stopAudio() async {
    if (currentlyPlayingIndex == null) return;  // Don't stop if nothing is playing
    
    try {
      debugPrint('Stopping audio playback...');
      setState(() {
        isPreparingAudio = true;
      });
      // First pause to ensure clean state transition
      await audioPlayer.pause();
      // Then stop
      await audioPlayer.stop();
      debugPrint('Audio playback stopped successfully');
      
      if (mounted) {
        setState(() {
          currentlyPlayingIndex = null;
          isPaused = false;
          isPreparingAudio = false;
        });
      }
    } catch (e) {
      debugPrint('Error stopping audio: $e');
      // Even if there's an error, reset the state
      if (mounted) {
        setState(() {
          currentlyPlayingIndex = null;
          isPaused = false;
          isPreparingAudio = false;
        });
      }
    }
  }

  void _toggleSelection(int index) {
    setState(() {
      if (selectedItems.contains(index)) {
        selectedItems.remove(index);
        isSelectionMode = selectedItems.isNotEmpty;
      } else {
        selectedItems.add(index);
        isSelectionMode = true;
      }
    });
  }

  void _selectAllItems() {
    setState(() {
      if (selectedItems.length == historyItems.length) {
        selectedItems.clear();
        isSelectionMode = false;
      } else {
        selectedItems = Set.from(List.generate(historyItems.length, (index) => index));
        isSelectionMode = true;
      }
    });
  }

  String _formatDateTime(String dateTimeString) {
    try {
      final dateTime = DateTime.parse(dateTimeString);
      return DateFormat('MMM dd, yyyy - hh:mm a').format(dateTime);
    } catch (e) {
      return dateTimeString;
    }
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ===============================
  // UI Building Code
  // ===============================

  AppBar _buildAppBar() {
    return AppBar(
      title: isSelectionMode
          ? Text('${selectedItems.length} selected')
          : const Text('Prediction History'),
      leading: isSelectionMode
          ? IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  selectedItems.clear();
                  isSelectionMode = false;
                });
              },
            )
          : null,
      actions: [
        if (isSelectionMode) ...[
          IconButton(
            icon: const Icon(Icons.select_all),
            onPressed: _selectAllItems,
            tooltip: 'Select all',
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _deleteSelectedItems,
            tooltip: 'Delete selected',
          ),
        ] else
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchHistory,
            tooltip: 'Refresh history',
          ),
      ],
    );
  }

  Widget _buildHistoryItem(int index) {
    final item = historyItems[index];
    final isPlaying = currentlyPlayingIndex == index;
    final isSelected = selectedItems.contains(index);
    final audioUrl = item['audio_url'];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      elevation: 4,
      color: isSelected ? Colors.orange[50] : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onLongPress: () => _toggleSelection(index),
        onTap: () {
          if (isSelectionMode) {
            _toggleSelection(index);
          } else if (isPlaying) {
            if (isPaused) {
              _playAudio(audioUrl);  // This will resume if paused
            } else {
              _pauseAudio();
            }
          } else {
            _playAudio(audioUrl);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (isSelectionMode)
                    Checkbox(
                      value: isSelected,
                      onChanged: (_) => _toggleSelection(index),
                    ),
                  Expanded(
                    child: Text(
                      item['filename'] ?? 'Unknown file',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isPlaying && isPreparingAudio)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                      ),
                    )
                  else
                    IconButton(
                      icon: Icon(
                        isPlaying 
                          ? (isPaused ? Icons.play_circle_fill : Icons.pause)
                          : Icons.play_circle_fill,
                        color: isPlaying 
                          ? (isPaused ? Colors.green : Colors.orange)
                          : Colors.green,
                        size: 28,
                      ),
                      onPressed: () {
                        if (isPlaying) {
                          if (isPaused) {
                            _playAudio(audioUrl);  // This will resume if paused
                          } else {
                            _pauseAudio();
                          }
                        } else {
                          _playAudio(audioUrl);
                        }
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _formatDateTime(item['timestamp']),
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Chip(
                    backgroundColor: Colors.orange[100],
                    label: Text(
                      item['prediction'] ?? 'Unknown',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.deepOrange,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(item['confidence'] * 100).toStringAsFixed(2)}%',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDF6F0),
      appBar: _buildAppBar(),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : historyItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.history, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text(
                        'No history available',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      TextButton(
                        onPressed: _fetchHistory,
                        child: const Text('Refresh'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchHistory,
                  child: ListView.builder(
                    itemCount: historyItems.length,
                    itemBuilder: (context, index) => _buildHistoryItem(index),
                  ),
                ),
    );
  }
}
