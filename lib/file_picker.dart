import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'selection.dart';
import 'history.dart';

class FilePickerPage extends StatefulWidget {
  const FilePickerPage({super.key});

  @override
  FilePickerPageState createState() => FilePickerPageState();
}

class FilePickerPageState extends State<FilePickerPage> {
  String? selectedFileName;
  String? selectedFilePath;
  String predictionResult = '';
  String confidenceLevel = '';
  bool isLoading = false;
  bool isPlaying = false;
  AudioPlayer audioPlayer = AudioPlayer();

  Future<void> _selectFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
    );

    if (result != null && result.files.isNotEmpty && result.files.single.path != null) {
      final file = result.files.single;
      setState(() {
        selectedFilePath = file.path;
        selectedFileName = file.name;
        predictionResult = '';
        confidenceLevel = '';
        isPlaying = false;
      });

      if (selectedFilePath != null) {
        await _sendFileToBackend(selectedFilePath!);
      }
    }
  }

  Future<void> _sendFileToBackend(String filePath) async {
    setState(() {
      isLoading = true;
      predictionResult = '';
      confidenceLevel = '';
    });

    try {
      var uri = Uri.parse("http://172.20.10.3:8000/predict");
      var request = http.MultipartRequest('POST', uri);

      String fileId = selectedFileName ?? 'file_${DateTime.now().millisecondsSinceEpoch}';
      request.fields['file_ID'] = fileId;
      request.files.add(await http.MultipartFile.fromPath('file', filePath));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      final data = jsonDecode(response.body);

      if (streamedResponse.statusCode == 200) {
        if (data['success'] == true) {
          setState(() {
            if (data['cat_detected'] == true) {
              predictionResult = data['cat_sound_prediction']?.toString() ?? 'Unknown';
              confidenceLevel = data['cat_sound_confidence'] != null 
                  ? "${(data['cat_sound_confidence'] * 100).toStringAsFixed(2)}%"
                  : "0.00%";
            } else {
              predictionResult = "Not a cat sound";
              confidenceLevel = data['cat_detector_confidence'] != null 
                  ? "${(data['cat_detector_confidence'] * 100).toStringAsFixed(2)}%"
                  : "0.00%";
            }
          });
        } else {
          setState(() {
            predictionResult = "Prediction failed";
            confidenceLevel = "0.00%";
          });
        }
      } else if (streamedResponse.statusCode == 400) {
        // Handle 400 error specifically
        setState(() {
          predictionResult = "Not a cat sound";
          confidenceLevel = data['cat_detector_confidence'] != null 
              ? "${(data['cat_detector_confidence'] * 100).toStringAsFixed(2)}%"
              : "0.00%";
        });
      } else {
        setState(() {
          predictionResult = "Server error: ${streamedResponse.statusCode}";
          confidenceLevel = "0.00%";
        });
      }
    } catch (e) {
      setState(() {
        predictionResult = "Error: ${e.toString()}";
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _togglePlayback() async {
    if (selectedFilePath == null) return;

    if (isPlaying) {
      await audioPlayer.pause();
    } else {
      await audioPlayer.play(DeviceFileSource(selectedFilePath!));
    }

    setState(() {
      isPlaying = !isPlaying;
    });
  }

  Widget _buildCard({required Widget child, Color? color}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 18),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: color ?? Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 12,
              offset: Offset(0, 6),
            )
          ],
        ),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDF7F3),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // Top bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, size: 28),
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const ChooseModePage()),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.history, size: 28),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const HistoryPage()),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 10),
            const Text(
              "📁 File Picker Mode",
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Color(0xFF333333),
              ),
            ),

            // File Picker UI
            _buildCard(
              child: GestureDetector(
                onTap: _selectFile,
                child: Row(
                  children: [
                    const Icon(Icons.folder_open, color: Color(0xFFFF7B54), size: 28),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        selectedFileName ?? 'Tap to select an audio file',
                        style: const TextStyle(fontSize: 16, color: Colors.black87),
                      ),
                    ),
                    if (selectedFilePath != null)
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey),
                        onPressed: () {
                          setState(() {
                            selectedFileName = null;
                            selectedFilePath = null;
                            predictionResult = '';
                            confidenceLevel = '';
                            isPlaying = false;
                          });
                          audioPlayer.stop();
                        },
                      ),
                  ],
                ),
              ),
            ),

            // Audio Player
            if (selectedFilePath != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                        color: const Color(0xFFD2691E),
                        size: 36,
                      ),
                      onPressed: _togglePlayback,
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      "Preview Audio",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),

            // Prediction Result
            _buildCard(
              color: const Color(0xFFFF7B54),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "🎯 Prediction Result",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (isLoading)
                    const Center(child: CircularProgressIndicator(color: Colors.white))
                  else if (predictionResult.isNotEmpty)
                    Column(
                      children: [
                        // Result
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            predictionResult,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Confidence
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFCE8DC),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            confidenceLevel.isNotEmpty
                                ? '$confidenceLevel confidence'
                                : '',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFFB45309),
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Text(
                        "Your prediction result will appear here.",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
