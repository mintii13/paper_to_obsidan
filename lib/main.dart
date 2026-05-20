import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

//Test kodus here
void main() {
  runApp(const PaperToObsidianApp());
}

class PaperToObsidianApp extends StatelessWidget {
  const PaperToObsidianApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Paper to Obsidian',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4), // Deep Purple Material 3
          background: Colors.grey.shade100, // Nền xám nhạt cho app
        ),
        useMaterial3: true,
        // Chuẩn hóa UI cho toàn bộ TextField trong app
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade100,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none, // Bỏ viền cứng
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
      home: const MainScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  // =========================================================================
  // BẮT ĐẦU PHẦN LOGIC (GIỮ NGUYÊN 100%)
  // =========================================================================
  String vaultPath = 'D:\\FPTU-sourse\\Research_Paper';
  String apiUrl = 'http://localhost:11434';
  http.Client? _client;
  File? selectedPdf;
  bool isLoading = false;
  String statusText = 'Sẵn sàng';

  final _titleCtrl = TextEditingController();
  final _authorsCtrl = TextEditingController();
  final _venueCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();
  final _problemCtrl = TextEditingController();
  final _keywordsCtrl = TextEditingController();
  final _limitationCtrl = TextEditingController();
  final _datasetCtrl = TextEditingController();
  final _summaryCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      vaultPath = prefs.getString('vaultPath') ?? '';
      apiUrl = prefs.getString('apiUrl') ?? 'http://localhost:11434';
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vaultPath', vaultPath);
    await prefs.setString('apiUrl', apiUrl);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Saved settings!')));
  }

  Future<void> _pickPdf() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null) {
      setState(() {
        selectedPdf = File(result.files.single.path!);
        statusText = 'Selected: ${p.basename(selectedPdf!.path)}';
      });
      _processPdf();
    }
  }

  Future<void> _processPdf() async {
    if (selectedPdf == null) return;
    setState(() {
      isLoading = true;
      statusText = 'Extracting text...';
    });

    try {
      final PdfDocument document = PdfDocument(
        inputBytes: selectedPdf!.readAsBytesSync(),
      );
      String extractedText = PdfTextExtractor(
        document,
      ).extractText(startPageIndex: 0, endPageIndex: 0);
      document.dispose();
      await _fetchMetadataFromOllama(extractedText);
    } catch (e) {
      setState(() => statusText = 'Extraction error: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _fetchMetadataFromOllama(String text) async {
    _client = http.Client();

    try {
      final response = await _client!.post(
        Uri.parse('$apiUrl/api/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "model": "qwen2.5:14b",
          "messages": [
            {
              "role": "system",
              "content":
                  "You are a research assistant. Extract metadata from the paper text. STRICT RULES: 1. Use ENGLISH only. 2. For lists (authors, keywords), separate items with COMMAS ONLY. 3. DO NOT use the word 'and' to connect items. 4. Return ONLY JSON with fields: title, authors, venue, year, problem, keywords, limitation, dataset, summary. 5. If any field is missing, return it as Not Given.",
            },
            {"role": "user", "content": "Text from first page: $text"},
          ],
          "format": "json",
          "stream": false,
          "options": {"temperature": 0.1},
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final metadata = jsonDecode(data['message']['content']);

        if (!mounted) return;

        setState(() {
          _titleCtrl.text = metadata['title'] ?? '';
          _authorsCtrl.text = metadata['authors'] ?? '';
          _venueCtrl.text = metadata['venue'] ?? '';
          _yearCtrl.text = metadata['year']?.toString() ?? '';
          _problemCtrl.text = metadata['problem'] ?? '';
          _keywordsCtrl.text = metadata['keywords'] ?? '';
          _limitationCtrl.text = metadata['limitation'] ?? '';
          _datasetCtrl.text = metadata['dataset'] ?? '';
          _summaryCtrl.text = metadata['summary'] ?? '';
          statusText = 'Success! Please review the metadata.';
        });
      }
    } catch (e) {
      if (statusText != 'Đã dừng trích xuất. Bạn có thể chọn file khác.') {
        setState(() => statusText = 'AI Error: $e');
      }
    } finally {
      _client?.close();
      _client = null;
      setState(() => isLoading = false);
    }
  }

  void _cancelExtraction() {
    if (_client != null) {
      _client!.close();
      _client = null;
      setState(() {
        isLoading = false;
        statusText = 'Đã dừng trích xuất. Bạn có thể chọn file khác.';
      });
    }
  }

  Future<void> _createInternalNotes(String input, String folderName) async {
    if (input.trim().isEmpty || input.toLowerCase() == "not given") return;

    try {
      final directory = Directory(p.join(vaultPath, folderName));
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      List<String> items = input.split(',').map((e) => e.trim()).toList();
      for (var item in items) {
        if (item.isEmpty || item.toLowerCase() == "not given") continue;

        String safeName = item.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        File file = File(p.join(directory.path, '$safeName.md'));

        if (!await file.exists()) {
          await file.writeAsString(
            '# $item\n\n*Generated by Paper to Obsidian*',
          );
        }
      }
    } catch (e) {
      debugPrint('Error creating internal notes for $folderName: $e');
    }
  }

  Future<void> _saveToObsidian() async {
    if (vaultPath.isEmpty || selectedPdf == null) return;

    try {
      final paperDirPath = p.join(vaultPath, "Papers");
      final paperDir = Directory(paperDirPath);
      if (!await paperDir.exists()) await paperDir.create(recursive: true);

      String formatYamlList(String input, String folderName) {
        if (input.trim().isEmpty || input.toLowerCase() == "not given")
          return "";
        return input
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .map((e) => '\n  - "[[$folderName/$e]]"')
            .join('');
      }

      String formatDisplayLinks(String input, String folderName) {
        if (input.trim().isEmpty || input.toLowerCase() == "not given")
          return "Not Given";
        return input
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .map((e) => '[[$folderName/$e]]')
            .join(', ');
      }

      String absPath = selectedPdf!.path.replaceAll(r'\', '/');
      if (!absPath.startsWith('/')) absPath = '/$absPath';
      String fileUri = "file://$absPath";

      String markdownContent =
          '''---
title: "${_titleCtrl.text.replaceAll('"', '\\"')}"
authors:${formatYamlList(_authorsCtrl.text, "Authors")}
venue: "[[Venues/${_venueCtrl.text}]]"
year: "[[Years/${_yearCtrl.text}]]"
keywords:${formatYamlList(_keywordsCtrl.text, "Tags")}
---
# ${_titleCtrl.text}

**Source PDF:** [Open Paper](<$fileUri>)

## 1. Summary
${_summaryCtrl.text}

## 2. Metadata Connections
- **Authors:** ${formatDisplayLinks(_authorsCtrl.text, "Authors")}
- **Year:** [[Years/${_yearCtrl.text}]]
- **Venue:** [[Venues/${_venueCtrl.text}]]
- **Datasets:** ${formatDisplayLinks(_datasetCtrl.text, "Datasets")}
- **Keywords:** ${formatDisplayLinks(_keywordsCtrl.text, "Tags")}

## 3. Research Details
- **Problem Statement:** ${_problemCtrl.text}
- **Dataset Detail:** ${_datasetCtrl.text}
- **Limitations:** ${_limitationCtrl.text}
''';

      String safeTitle = _titleCtrl.text.replaceAll(
        RegExp(r'[\\/:*?"<>|]'),
        '_',
      );
      String mdFileName = '${safeTitle.isEmpty ? 'Untitled' : safeTitle}.md';
      File mdFile = File(p.join(paperDirPath, mdFileName));
      await mdFile.writeAsString(markdownContent);

      await _createInternalNotes(_authorsCtrl.text, "Authors");
      await _createInternalNotes(_keywordsCtrl.text, "Tags");
      await _createInternalNotes(_datasetCtrl.text, "Datasets");
      if (_yearCtrl.text.isNotEmpty)
        await _createInternalNotes(_yearCtrl.text, "Years");
      if (_venueCtrl.text.isNotEmpty)
        await _createInternalNotes(_venueCtrl.text, "Venues");

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã lưu vào Papers/ và các thư mục Metadata!'),
        ),
      );
      setState(() => statusText = 'Lưu thành công!');
    } catch (e) {
      setState(() => statusText = 'Lỗi: $e');
    }
  }
  // =========================================================================
  // KẾT THÚC PHẦN LOGIC
  // =========================================================================

  // =========================================================================
  // BẮT ĐẦU PHẦN UI ĐÃ ĐƯỢC LÀM ĐẸP
  // =========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      appBar: AppBar(
        title: const Text(
          'Paper to Obsidian',
          style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent, // Tránh ám màu của M3
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: FilledButton.tonalIcon(
              onPressed: () => _showSettingsDialog(context),
              icon: const Icon(Icons.settings, size: 18),
              label: const Text('Settings'),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ==========================================
            // CỘT 1: ACTIONS (Bảng điều khiển bên trái)
            // ==========================================
            SizedBox(
              width: 260,
              child: _buildPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Actions',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: isLoading ? null : _pickPdf,
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('Select Paper (PDF)'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Box hiển thị Status
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isLoading
                            ? Colors.blue.shade50
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isLoading
                              ? Colors.blue.shade200
                              : Colors.transparent,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Status',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 14,
                              color: isLoading
                                  ? Colors.blue.shade700
                                  : Colors.black87,
                              fontWeight: isLoading
                                  ? FontWeight.w500
                                  : FontWeight.normal,
                            ),
                          ),
                          if (isLoading) ...[
                            const SizedBox(height: 16),
                            const LinearProgressIndicator(
                              borderRadius: BorderRadius.all(
                                Radius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _cancelExtraction,
                                icon: const Icon(
                                  Icons.stop_circle_outlined,
                                  size: 18,
                                ),
                                label: const Text('Cancel'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red.shade400,
                                  side: BorderSide(color: Colors.red.shade200),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const Spacer(),

                    // Nút Save nổi bật
                    FilledButton.icon(
                      onPressed: selectedPdf == null ? null : _saveToObsidian,
                      icon: const Icon(Icons.save_alt),
                      label: const Text(
                        'Save to Obsidian',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 64),
                        backgroundColor: Colors.green.shade600,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 20), // Khoảng cách giữa các cột
            // ==========================================
            // CỘT 2: PDF PREVIEW (Xem trước tài liệu)
            // ==========================================
            Expanded(
              flex: 5,
              child: _buildPanel(
                padding: EdgeInsets.zero, // Bỏ padding để PDF tràn viền card
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Icon(
                            Icons.visibility,
                            size: 20,
                            color: Colors.grey.shade700,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Document Preview',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: selectedPdf != null
                          ? SfPdfViewer.file(selectedPdf!)
                          : Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.find_in_page_outlined,
                                    size: 64,
                                    color: Colors.grey.shade300,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No PDF selected',
                                    style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 20),

            // ==========================================
            // CỘT 3: METADATA EDIT (Chỉnh sửa thông tin)
            // ==========================================
            Expanded(
              flex: 4,
              child: _buildPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          size: 20,
                          color: Colors.purple.shade400,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'AI Extracted Metadata',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            _buildTextField('Title', _titleCtrl),
                            _buildTextField('Authors', _authorsCtrl),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildTextField('Venue', _venueCtrl),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildTextField('Year', _yearCtrl),
                                ),
                              ],
                            ),
                            _buildTextField('Tags / Keywords', _keywordsCtrl),
                            _buildTextField(
                              'Dataset',
                              _datasetCtrl,
                              maxLines: 2,
                            ),
                            _buildTextField(
                              'Problem Statement',
                              _problemCtrl,
                              maxLines: 3,
                            ),
                            _buildTextField(
                              'Limitations',
                              _limitationCtrl,
                              maxLines: 2,
                            ),
                            _buildTextField(
                              'Summary',
                              _summaryCtrl,
                              maxLines: 5,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Widget hỗ trợ tạo khung Card đổ bóng cho các cột
  Widget _buildPanel({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      clipBehavior: Clip.antiAlias, // Cắt cúp nội dung (như PDF) theo bo góc
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  // Hàm build TextField đã được làm đẹp (áp dụng theme từ MaterialApp)
  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.grey.shade600),
          alignLabelWithHint:
              maxLines > 1, // Đẩy label lên trên cùng nếu là multiline
        ),
      ),
    );
  }

  void _showSettingsDialog(BuildContext context) {
    TextEditingController vCtrl = TextEditingController(text: vaultPath);
    TextEditingController apiCtrl = TextEditingController(text: apiUrl);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Preferences',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: vCtrl,
                decoration: const InputDecoration(
                  labelText: 'Obsidian Vault Path',
                  prefixIcon: Icon(Icons.folder_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: apiCtrl,
                decoration: const InputDecoration(
                  labelText: 'Ollama API URL',
                  prefixIcon: Icon(Icons.link),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                vaultPath = vCtrl.text;
                apiUrl = apiCtrl.text;
              });
              _saveSettings();
              Navigator.pop(context);
            },
            child: const Text('Save Changes'),
          ),
        ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
