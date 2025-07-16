import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:record/record.dart';
import 'dart:typed_data';

class RealTimePage extends StatefulWidget {
  const RealTimePage({super.key});

  @override
  RealTimePageState createState() => RealTimePageState();
}

class RealTimePageState extends State<RealTimePage> {
  late final AudioRecorder _audioRecorder;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isRecording = false;
  bool _isAnalyzing = false;
  String _predictionResult = '';
  String _confidenceLevel = '';
  Timer? _analysisTimer;
  String? _currentRecordingPath;
  int _recordingDuration = 0;
  Timer? _durationTimer;
  static const int minRecordingDuration = 2;
  static const int minFileSize = 256;
  bool _isFirstLoad = true;
  double _currentVolume = 0.0;
  bool _isTestMode = false;
  Timer? _volumeCheckTimer;

  @override
  void initState() {
    super.initState();
    _audioRecorder = AudioRecorder();
    _initRecorder();
    _requestPermissions();
  }

  @override
  void dispose() {
    _stopRecording();
    _audioPlayer.dispose();
    _analysisTimer?.cancel();
    _durationTimer?.cancel();
    _audioRecorder.dispose();
    _cleanupRecording();
    super.dispose();
  }

  Future<void> _initRecorder() async {
    try {
      debugPrint('Initializing recorder...');
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        debugPrint('Microphone permission denied');
        return;
      }

      // Initialize the recorder
      if (!await _audioRecorder.hasPermission()) {
        debugPrint('Recorder permission denied');
        return;
      }

      debugPrint('Recorder initialized successfully');
    } catch (e) {
      debugPrint('Error initializing recorder: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to initialize recorder: $e')),
        );
      }
    }
  }

  Future<void> _cleanupRecording() async {
    if (_currentRecordingPath != null) {
      try {
        final file = File(_currentRecordingPath!);
        if (await file.exists()) {
          debugPrint('Skipping cleanup - keeping recording: ${file.path}');
          // Temporarily disabled cleanup
          // await file.delete();
          // debugPrint('Previous recording deleted successfully');
        } else {
          debugPrint('No previous recording file found to clean up');
        }
      } catch (e) {
        debugPrint('Error in cleanup: $e');
      }
      // Don't clear the path so we can access it later
      // _currentRecordingPath = null;
    }
  }

  Future<String> _getRecordingPath() async {
    try {
      // Get external storage directory
      final directory = await getExternalStorageDirectory();
      if (directory == null) {
        throw Exception('Could not access external storage');
      }

      // Create recordings directory
      final recordingsDir = Directory('${directory.path}/recordings');
      if (!await recordingsDir.exists()) {
        await recordingsDir.create(recursive: true);
      }
      
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = '${recordingsDir.path}/recording_$timestamp.wav';
      debugPrint('Generated recording path: $path');
      return path;
    } catch (e) {
      debugPrint('Error getting recording path: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating recording directory: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      rethrow;
    }
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      // Request storage permission
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        debugPrint('Storage permission denied');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Storage permission is required to save recordings'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    }
    
    // Request microphone permission
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      debugPrint('Microphone permission denied');
      if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission is required to record audio'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _writeWavHeader(String filePath, int dataSize) async {
    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      
      // Create WAV header
      final header = ByteData(44);
      
      // RIFF chunk descriptor
      header.setUint8(0, 'R'.codeUnitAt(0));
      header.setUint8(1, 'I'.codeUnitAt(0));
      header.setUint8(2, 'F'.codeUnitAt(0));
      header.setUint8(3, 'F'.codeUnitAt(0));
      header.setUint32(4, 36 + dataSize, Endian.little); // File size - 8
      header.setUint8(8, 'W'.codeUnitAt(0));
      header.setUint8(9, 'A'.codeUnitAt(0));
      header.setUint8(10, 'V'.codeUnitAt(0));
      header.setUint8(11, 'E'.codeUnitAt(0));
      
      // fmt sub-chunk
      header.setUint8(12, 'f'.codeUnitAt(0));
      header.setUint8(13, 'm'.codeUnitAt(0));
      header.setUint8(14, 't'.codeUnitAt(0));
      header.setUint8(15, ' '.codeUnitAt(0));
      header.setUint32(16, 16, Endian.little); // Subchunk1Size
      header.setUint16(20, 1, Endian.little); // AudioFormat (1 for PCM)
      header.setUint16(22, 1, Endian.little); // NumChannels (1 for mono)
      header.setUint32(24, 48000, Endian.little); // SampleRate
      header.setUint32(28, 48000 * 2, Endian.little); // ByteRate (SampleRate * NumChannels * BitsPerSample/8)
      header.setUint16(32, 2, Endian.little); // BlockAlign (NumChannels * BitsPerSample/8)
      header.setUint16(34, 16, Endian.little); // BitsPerSample
      
      // data sub-chunk
      header.setUint8(36, 'd'.codeUnitAt(0));
      header.setUint8(37, 'a'.codeUnitAt(0));
      header.setUint8(38, 't'.codeUnitAt(0));
      header.setUint8(39, 'a'.codeUnitAt(0));
      header.setUint32(40, dataSize, Endian.little); // Subchunk2Size
      
      // Write header and data to new file
      final newPath = filePath.replaceAll('.wav', '_with_header.wav');
      final newFile = File(newPath);
      await newFile.writeAsBytes(header.buffer.asUint8List() + bytes);
      
      // Replace original file with new file
      await file.delete();
      await newFile.rename(filePath);
      
      debugPrint('WAV header written successfully');
      debugPrint('Header values:');
      debugPrint('File size: ${36 + dataSize}');
      debugPrint('Audio Format: 1 (PCM)');
      debugPrint('Channels: 1 (Mono)');
      debugPrint('Sample Rate: 48000');
      debugPrint('Byte Rate: ${48000 * 2}');
      debugPrint('Block Align: 2');
      debugPrint('Bits per Sample: 16');
      debugPrint('Data Size: $dataSize');
    } catch (e) {
      debugPrint('Error writing WAV header: $e');
    }
  }

  Future<void> _startRecording() async {
    if (!mounted) return;

    // Clean up any existing recording first
    await _cleanupRecording();

    final status = await Permission.microphone.request();
    if (!status.isGranted) {
    if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission denied')),
        );
      }
      return;
    }

    _currentRecordingPath = await _getRecordingPath();
    debugPrint('New recording path: $_currentRecordingPath');

    try {
      debugPrint('Starting recording...');
      
      if (_currentRecordingPath == null) {
        throw Exception('Recording path is null');
      }

      // Ensure recorder is initialized
      if (!await _audioRecorder.hasPermission()) {
        throw Exception('Recorder permission not granted');
      }

      await _audioRecorder.start(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,  // Use PCM format instead of WAV
          sampleRate: 44100,                // Standard sample rate for better compatibility
          numChannels: 1,                   // Mono
          bitRate: 128000,                  // Standard bit rate
        ),
        path: _currentRecordingPath!,
      );

      setState(() {
        _isRecording = true;
        _recordingDuration = 0;
        _isFirstLoad = false;
      });

      _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) setState(() => _recordingDuration++);
      });

      // Start volume monitoring
      _startVolumeMonitoring();

      // Start analysis after minimum duration
      await Future.delayed(const Duration(seconds: minRecordingDuration));
      _analysisTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
        if (_isRecording && mounted) {
          await _analyzeAudio();
          // Stop recording after each 3-second analysis
          await _stopRecording();
        }
      });
    } catch (e) {
      debugPrint('Recording error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Recording failed: $e')),
        );
      }
      await _stopRecording();
    }
  }

  void _startVolumeMonitoring() {
    _volumeCheckTimer?.cancel();
    _volumeCheckTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      if (_isRecording) {
        try {
          final amplitude = await _audioRecorder.getAmplitude();
          setState(() {
            // Adjust amplitude calculation for Huawei devices
            double normalizedAmplitude = amplitude.current.abs() / 32768.0;
            // Apply a multiplier to boost the volume level
            _currentVolume = (normalizedAmplitude * 2.0).clamp(0.0, 1.0);
            debugPrint('Raw amplitude: ${amplitude.current}, Normalized: $normalizedAmplitude, Final volume: $_currentVolume');
          });
        } catch (e) {
          debugPrint('Error getting amplitude: $e');
        }
      }
    });
  }

  Future<void> _analyzeAudio() async {
    if (_isAnalyzing || _currentRecordingPath == null) return;
    _isAnalyzing = true;

    try {
      final file = File(_currentRecordingPath!);
      if (!await file.exists()) {
        throw Exception('Recording file not found');
      }

      final bytes = await file.readAsBytes();
      if (bytes.length <= 44) { // Only header
        throw Exception('No audio data recorded');
      }

      // Calculate actual data size (excluding header)
      final dataSize = bytes.length - 44;
      
      // Write proper WAV header
      await _writeWavHeader(_currentRecordingPath!, dataSize);

      // Create multipart request for real-time analysis
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('http://172.20.10.3:8000/realtime_predict'),
      );

      // Add audio data with explicit content type
      request.files.add(
        http.MultipartFile.fromBytes(
          'audio',
          bytes,
          filename: 'recording_${DateTime.now().millisecondsSinceEpoch}.wav',
          contentType: MediaType('audio', 'wav'),
        ),
      );

      debugPrint('Sending request to server...');
      var response = await request.send();
      var responseBody = await response.stream.bytesToString();
      debugPrint('Server response status: ${response.statusCode}');
      debugPrint('Server response body: $responseBody');

      if (response.statusCode == 200) {
        var data = json.decode(responseBody);
        if (mounted) {
          setState(() {
          if (data['cat_detected'] == true) {
              _predictionResult = data['prediction'] ?? 'Unknown';
              _confidenceLevel = '${(data['confidence'] * 100).toStringAsFixed(2)}%';
          } else {
              _predictionResult = 'Not a cat sound';
              _confidenceLevel = '${(data['cat_detector_confidence'] * 100).toStringAsFixed(2)}%';
            }
            });
        }
      } else {
        var errorData = json.decode(responseBody);
        throw Exception(errorData['detail'] ?? 'Analysis failed');
      }
    } catch (e) {
      debugPrint('Analysis error: $e');
      if (mounted) {
        setState(() {
          _predictionResult = 'Error: ${e.toString()}';
          _confidenceLevel = '';
        });
      }
    } finally {
      _isAnalyzing = false;
    }
  }

  Future<void> _stopRecording() async {
    debugPrint('Stopping recording...');
    _durationTimer?.cancel();
    _analysisTimer?.cancel();
    _volumeCheckTimer?.cancel();
    
    if (_isRecording) {
      try {
        await _audioRecorder.stop();
        debugPrint('Recorder stopped successfully');
      } catch (e) {
        debugPrint('Error stopping recorder: $e');
      }
    }
    
    setState(() {
      _isRecording = false;
      _isAnalyzing = false;
      _recordingDuration = 0;
    });

    if (_currentRecordingPath != null) {
      final file = File(_currentRecordingPath!);
      if (await file.exists()) {
        final size = await file.length();
        debugPrint('Recording saved to: ${file.path}');
        debugPrint('Final recording size: $size bytes');
      }
    }

    // Temporarily disabled cleanup
    // await _cleanupRecording();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDF6F0),
      appBar: AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.black87),
        onPressed: () => Navigator.pop(context),
      ),
        title: const Text(
        'Real-time Mode',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              _isTestMode ? Icons.science : Icons.science_outlined,
              color: _isTestMode ? Colors.blue : Colors.black87,
            ),
            onPressed: () {
              setState(() {
                _isTestMode = !_isTestMode;
              });
            },
            tooltip: 'Test Mode',
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // Main Content
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 100),
      child: Column(
        children: [
                  // Main Box
                  Expanded(
                    flex: _isTestMode && _isRecording ? 2 : 3,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFE5B4),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.orangeAccent, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.orange.withOpacity(0.2),
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Center(
                        child: _isFirstLoad
                            ? const Text(
                                '🐾 Press the mic to start listening',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black87,
                                ),
                                textAlign: TextAlign.center,
                              )
                            : _isRecording
                                ? _isAnalyzing
                                    ? Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const CircularProgressIndicator(
                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                                          ),
                                          const SizedBox(height: 16),
          Text(
                                            'Analyzing...',
                                            style: TextStyle(
              fontSize: 18,
                                              color: Colors.black87.withOpacity(0.8),
                                              fontWeight: FontWeight.w500,),),
                                          if (_recordingDuration > 0) ...[
                                            const SizedBox(height: 12),
            Text(
                                              '$_recordingDuration s',
                                              style: TextStyle(
                fontSize: 16,
                                                color: Colors.black87.withOpacity(0.6),
              ),
            ),
          ],
                                        ],
                                      )
                                    : Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Text(
                                            '🎙️ Listening...',
                                            style: TextStyle(
                                              fontSize: 24,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.black87,
                                            ),
                                          ),
                                          if (_recordingDuration > 0) ...[
                                            const SizedBox(height: 12),
                                            Text(
                                              '$_recordingDuration s',
                                              style: TextStyle(
                                                fontSize: 18,
                                                color: Colors.black87.withOpacity(0.6),),),
                                                ],
                                        ],
                                      )
                                : _predictionResult.isNotEmpty
                                    ? Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            _predictionResult,
                                            style: const TextStyle(
                                              fontSize: 28,
                                              color: Colors.blue,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: Colors.green.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(20),
                                              border: Border.all(color: Colors.green.withOpacity(0.3)),
                                            ),
                                            child: Text(
                                              'Confidence: $_confidenceLevel',
                                              style: const TextStyle(
                                                fontSize: 18,
                                                color: Colors.green,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ],
                                      )
                                    : const Text(
                                        '🎙️ Listening...',
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black87,
                                        ),
                                      ),
                      ),
                    ),
                  ),
                  // Test Mode Box
                  if (_isTestMode && _isRecording)
                    Expanded(
                      flex: 1,
                      child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 20),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.blue.withOpacity(0.3)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
                                Icon(
                                  Icons.volume_up,
                                  color: Colors.blue.withOpacity(0.7),
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  'Volume Level',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              height: 20,
                              child: Stack(
                                children: [
                                  Container(
                                    width: double.infinity,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[200],
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 20,
                                    child: FractionallySizedBox(
                                      widthFactor: _currentVolume.clamp(0.0, 1.0),
                                      child: Container(
                                        height: 20,
                                        decoration: BoxDecoration(
                                          color: _currentVolume > 0.7
                                              ? Colors.red.withOpacity(0.8)
                                              : _currentVolume > 0.3
                                                  ? Colors.orange.withOpacity(0.8)
                                                  : Colors.green.withOpacity(0.8),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${(_currentVolume * 100).toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontSize: 14,
                                color: _currentVolume > 0.7
                                    ? Colors.red.withOpacity(0.8)
                                    : _currentVolume > 0.3
                                        ? Colors.orange.withOpacity(0.8)
                                        : Colors.green.withOpacity(0.8),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: (_currentVolume > 0.7
                                        ? Colors.red
                                        : _currentVolume > 0.3
                                            ? Colors.orange
                                            : Colors.green).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: (_currentVolume > 0.7
                                          ? Colors.red
                                          : _currentVolume > 0.3
                                              ? Colors.orange
                                              : Colors.green).withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _currentVolume > 0.7
                                        ? Icons.warning
                                        : _currentVolume > 0.3
                                            ? Icons.check_circle
                                            : Icons.volume_down,
                                    size: 14,
                                    color: _currentVolume > 0.7
                                        ? Colors.red.withOpacity(0.8)
                                        : _currentVolume > 0.3
                                            ? Colors.orange.withOpacity(0.8)
                                            : Colors.green.withOpacity(0.8),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _currentVolume > 0.7
                                        ? 'Volume too high!'
                                        : _currentVolume > 0.3
                                            ? 'Good volume level'
                                            : 'Volume too low',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _currentVolume > 0.7
                                          ? Colors.red.withOpacity(0.8)
                                          : _currentVolume > 0.3
                                              ? Colors.orange.withOpacity(0.8)
                                              : Colors.green.withOpacity(0.8),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Mic Button at Bottom
            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
              onTap: _isRecording ? _stopRecording : _startRecording,
              child: Container(
                    padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                      color: _isRecording ? Colors.redAccent : const Color(0xFFFF7B54),
                  boxShadow: [
                    BoxShadow(
                          color: (_isRecording ? Colors.redAccent : const Color(0xFFFF7B54)).withOpacity(0.3),
                          blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Icon(
                  _isRecording ? Icons.stop : Icons.mic,
                      size: 36,
                  color: Colors.white,
                ),
              ),
            ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}