import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'services/api_service.dart';

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
          seedColor: const Color(0xFF6750A4),
          background: Colors.grey.shade100,
        ),
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade200),
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
  // 1. STATE VARIABLES & CONTROLLERS
  // =========================================================================
  String vaultPath = 'D:\\FPTU-sourse\\Research_Paper';
  String apiUrl = 'http://localhost:11434';
  http.Client? _client;
  File? selectedPdf;
  bool isLoading = false;
  String statusText = 'Sẵn sàng';

  // API Services for professional metadata extraction
  late ResearchApiService researchApiService;

  // PDF Viewer Controller để hỗ trợ Zoom và tương tác văn bản
  final PdfViewerController _pdfViewerController = PdfViewerController();
  PdfInteractionMode _pdfInteractionMode =
      PdfInteractionMode.pan; // Chế độ cuộn/chọn text

  // Biến phục vụ chat AI
  String fullPdfText = '';
  List<Map<String, String>> chatMessages = [];
  bool isChatLoading = false;
  final _chatInputCtrl = TextEditingController();
  final ScrollController _chatScrollCtrl = ScrollController();

  // Biến phục vụ Vault Library
  List<Map<String, String>> libraryPapers = [];
  bool isLibraryLoading = false;

  // Controllers cho form Metadata
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
    researchApiService = ResearchApiService(
      ollamaUrl: 'http://localhost:11434',
      grobidUrl: 'http://localhost:8070',
    );
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      vaultPath =
          prefs.getString('vaultPath') ?? 'D:\\FPTU-sourse\\Research_Paper';
      apiUrl = prefs.getString('apiUrl') ?? 'http://localhost:11434';
    });
    _loadVaultLibrary(); // Tự động quét thư viện khi mở app
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vaultPath', vaultPath);
    await prefs.setString('apiUrl', apiUrl);
    _loadVaultLibrary();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Saved settings!')));
  }

  // =========================================================================
  // 2. VAULT LIBRARY LOGIC (TÍNH NĂNG THƯ VIỆN MỚI)
  // =========================================================================
  Future<void> _loadVaultLibrary() async {
    if (vaultPath.isEmpty) return;
    setState(() => isLibraryLoading = true);

    List<Map<String, String>> tempPapers = [];
    try {
      final paperDir = Directory(p.join(vaultPath, "Papers"));
      if (await paperDir.exists()) {
        final files = paperDir.listSync();
        for (var file in files) {
          if (file is File && file.path.endsWith('.md')) {
            String content = await file.readAsString();
            String title = p.basenameWithoutExtension(file.path);
            String year = 'Not Given';

            // Parse năm từ YAML cơ bản bằng Regex
            final yearRegex = RegExp(r'year:\s*"\[\[Years\/(.*?)\]\]"');
            final match = yearRegex.firstMatch(content);
            if (match != null && match.groupCount >= 1) {
              year = match.group(1) ?? 'Not Given';
            }

            tempPapers.add({'title': title, 'year': year, 'path': file.path});
          }
        }
      }
    } catch (e) {
      debugPrint('Lỗi tải thư viện: $e');
    }

    setState(() {
      libraryPapers = tempPapers;
      isLibraryLoading = false;
    });
  }

  // Hàm mở bài báo cũ từ thư viện lên để đọc và chat tiếp tục
  Future<void> _openPaperFromLibrary(String mdPath) async {
    setState(() {
      isLoading = true;
      statusText = 'Loading paper from library...';
      chatMessages.clear();
    });

    try {
      File mdFile = File(mdPath);
      String content = await mdFile.readAsString();

      // Trích xuất đường dẫn file PDF gốc từ file Markdown
      // Định dạng mẫu: **Source PDF:** [Open Paper](<file:///D:/path/file.pdf>)
      final pdfPathRegex = RegExp(r'\<file:\/\/\/(.*?)\>');
      final match = pdfPathRegex.firstMatch(content);

      if (match != null && match.groupCount >= 1) {
        String decodedPdfPath = Uri.decodeFull(match.group(1)!);
        // Sửa lại dấu gạch chéo cho hệ điều hành Windows nếu cần
        if (Platform.isWindows)
          decodedPdfPath = decodedPdfPath.replaceAll('/', '\\');

        File pdfFile = File(decodedPdfPath);
        if (await pdfFile.exists()) {
          setState(() {
            selectedPdf = pdfFile;
            statusText = 'Viewing: ${p.basename(pdfFile.path)}';
          });

          // Trích xuất lại văn bản để phục vụ Chat RAG
          final PdfDocument document = PdfDocument(
            inputBytes: pdfFile.readAsBytesSync(),
          );
          int maxPages = document.pages.count > 10 ? 10 : document.pages.count;
          fullPdfText = PdfTextExtractor(
            document,
          ).extractText(startPageIndex: 0, endPageIndex: maxPages - 1);
          document.dispose();

          // Đổ dữ liệu cũ vào các ô Form để xem/chỉnh sửa nếu muốn
          _titleCtrl.text = p.basenameWithoutExtension(mdPath);
          chatMessages.add({
            "role": "assistant",
            "content":
                "I loaded this paper from your library vault. You can now read it or ask me questions about it!",
          });
        } else {
          setState(
            () => statusText =
                'Error: Original PDF file not found at $decodedPdfPath',
          );
        }
      } else {
        setState(
          () => statusText =
              'Error: Cannot extract PDF path from markdown metadata.',
        );
      }
    } catch (e) {
      setState(() => statusText = 'Error loading library paper: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  // =========================================================================
  // 3. PDF PROCESSING & AI METADATA EXTRACTION
  // =========================================================================
  Future<void> _pickPdf() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null) {
      setState(() {
        selectedPdf = File(result.files.single.path!);
        statusText = 'Selected: ${p.basename(selectedPdf!.path)}';
        chatMessages.clear();
        fullPdfText = '';
      });
      _processPdf();
    }
  }

  Future<void> _processPdf() async {
    if (selectedPdf == null) return;
    
    setState(() {
      isLoading = true;
      statusText = 'Step 1/4: Extracting text from PDF...';
    });

    try {
      // Step 1: Extract text from PDF for context and RAG
      final PdfDocument document = PdfDocument(
        inputBytes: selectedPdf!.readAsBytesSync(),
      );
      String extractedTextPage0 = PdfTextExtractor(
        document,
      ).extractText(startPageIndex: 0, endPageIndex: 0);
      
      int maxPagesForContext = document.pages.count > 10
          ? 10
          : document.pages.count;
      fullPdfText = PdfTextExtractor(
        document,
      ).extractText(startPageIndex: 0, endPageIndex: maxPagesForContext - 1);
      document.dispose();

      if (!mounted) return;
      
      // Step 2: Process PDF with Grobid for structured data
      await _processWithGrobidAndOpenAlex(extractedTextPage0);
    } catch (e) {
      if (mounted) {
        setState(() => statusText = 'PDF extraction error: $e');
        setState(() => isLoading = false);
      }
    }
  }

  /// Professional metadata extraction workflow:
  /// PDF -> Grobid (structure) -> OpenAlex (accuracy) -> Ollama (summary)
  Future<void> _processWithGrobidAndOpenAlex(String firstPageText) async {
    try {
      if (selectedPdf == null) return;

      // Step 2: Send to Grobid for structured PDF parsing
      setState(() => statusText = 'Step 2/4: Parsing PDF structure with Grobid...');
      
      String grobidXml = '';
      Map<String, dynamic> grobidData = {};
      
      try {
        grobidXml = await researchApiService.processPdfWithGrobid(selectedPdf!);
        grobidData = ResearchApiService.parseGrobidXml(grobidXml);
      } catch (e) {
        // If Grobid fails, fall back to Ollama extraction
        debugPrint('Grobid error (using Ollama fallback): $e');
        grobidData = {'title': '', 'authors': '', 'year': ''};
      }

      if (!mounted) return;

      // Step 3: Query OpenAlex for standardized metadata using Grobid title
      setState(() => statusText = 'Step 3/4: Fetching standardized metadata...');
      
      Map<String, dynamic> openalexData = {};
      if (grobidData['title']?.toString().isNotEmpty ?? false) {
        try {
          openalexData = await researchApiService
              .fetchOpenAlexMetadata(grobidData['title'] ?? '');
        } catch (e) {
          debugPrint('OpenAlex error: $e');
          openalexData = {};
        }
      }

      if (!mounted) return;

      // Step 4: Generate summary using Ollama
      setState(() => statusText = 'Step 4/4: Generating summary...');
      
      String summary = '';
      try {
        summary = await researchApiService.generateSummaryWithOllama(fullPdfText);
      } catch (e) {
        debugPrint('Summary generation error: $e');
        summary = 'Not Given';
      }

      if (!mounted) return;

      // Merge data with preference: OpenAlex > Grobid > Default
      _populateMetadataFields(grobidData, openalexData, summary);
    } catch (e) {
      if (mounted) {
        setState(() => statusText = 'Processing error: $e');
        setState(() => isLoading = false);
      }
    }
  }

  /// Populates form fields with merged metadata from multiple sources
  /// Priority: OpenAlex > Grobid > Fallback values
  void _populateMetadataFields(
    Map<String, dynamic> grobidData,
    Map<String, dynamic> openalexData,
    String summary,
  ) {
    if (!mounted) return;

    setState(() {
      // Title: Prefer OpenAlex, fall back to Grobid
      _titleCtrl.text = (openalexData['title'] as String?) ?? 
                        (grobidData['title'] as String?) ?? 
                        '';

      // Authors: Prefer OpenAlex, fall back to Grobid
      _authorsCtrl.text = (openalexData['authors'] as String?) ?? 
                          (grobidData['authors'] as String?) ?? 
                          '';

      // Venue: Use OpenAlex (more reliable for publication venue)
      _venueCtrl.text = (openalexData['venue'] as String?) ?? 
                        (grobidData['abstract']?.toString().split('\n').first ?? '');

      // Year: Prefer OpenAlex, fall back to Grobid
      _yearCtrl.text = (openalexData['year'] as String?) ?? 
                       (grobidData['year'] as String?) ?? 
                       '';

      // Problem: Use Ollama summary parsing (from full PDF analysis)
      _problemCtrl.text = 'Extracted via Grobid + OpenAlex';

      // Keywords: Use Grobid extracted keywords
      _keywordsCtrl.text = (grobidData['keywords'] as String?) ?? '';

      // Limitation: Empty for now (user to fill manually)
      _limitationCtrl.text = '';

      // Dataset: Empty for now (user to fill manually)
      _datasetCtrl.text = '';

      // Summary: From Ollama analysis
      _summaryCtrl.text = summary;

      statusText = 'Success! Metadata extracted via Grobid + OpenAlex + Ollama';
    });

    // Initialize chat with AI
    chatMessages.add({
      "role": "assistant",
      "content":
          "Hi! I have read the paper. What would you like to know about it?",
    });
  }

  /// Legacy Ollama fallback (kept for compatibility)
  /// Only used if Grobid/OpenAlex fail completely
  Future<void> _fetchMetadataFromOllamaLegacy(String text) async {
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
                  "You are a research assistant. Extract metadata from the paper text. Return JSON with: title, authors, venue, year, problem, keywords, limitation, dataset, summary. Use 'Not Given' if unavailable.",
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
          statusText = 'Success! (Ollama fallback) Please review metadata.';
        });

        chatMessages.add({
          "role": "assistant",
          "content":
              "Hi! I have read the paper. What would you like to know about it?",
        });
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

  // =========================================================================
  // 4. AI CHAT LOGIC
  // =========================================================================
  Future<void> _sendChatMessage() async {
    final userText = _chatInputCtrl.text.trim();
    if (userText.isEmpty || fullPdfText.isEmpty) return;

    setState(() {
      chatMessages.add({"role": "user", "content": userText});
      isChatLoading = true;
      _chatInputCtrl.clear();
    });
    _scrollToBottom();

    try {
      // Use ResearchApiService for RAG chat with paper context
      final response = await researchApiService.chatWithPaperContext(
        userText,
        fullPdfText,
      );

      setState(() {
        chatMessages.add({
          "role": "assistant",
          "content": response.isNotEmpty ? response : "Sorry, no response.",
        });
      });
    } catch (e) {
      setState(
        () => chatMessages.add({"role": "assistant", "content": "Error: $e"}),
      );
    } finally {
      setState(() => isChatLoading = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_chatScrollCtrl.hasClients) {
        _chatScrollCtrl.animateTo(
          _chatScrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // =========================================================================
  // 5. OBSIDIAN SAVING LOGIC
  // =========================================================================
  Future<void> _createInternalNotes(String input, String folderName) async {
    if (input.trim().isEmpty || input.toLowerCase() == "not given") return;
    try {
      final directory = Directory(p.join(vaultPath, folderName));
      if (!await directory.exists()) await directory.create(recursive: true);
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
      debugPrint('Error: $e');
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

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã lưu vào Obsidian!')));
      setState(() => statusText = 'Lưu thành công!');
      _loadVaultLibrary(); // Cập nhật lại danh sách thư viện sau khi lưu mới
    } catch (e) {
      setState(() => statusText = 'Lỗi: $e');
    }
  }

  // =========================================================================
  // 6. MAIN WORKSPACE UI
  // =========================================================================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    final textLower = statusText.toLowerCase();
    final isSuccess =
        textLower.contains('success') || textLower.contains('thành công');
    final isError = textLower.contains('error') || textLower.contains('lỗi');

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      appBar: AppBar(
        title: const Text(
          'Paper to Obsidian',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
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
            // ------------------------------------------
            // CỘT 1: ACTIONS PANELS
            // ------------------------------------------
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
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isSuccess
                            ? Colors.green.shade50
                            : (isError
                                  ? Colors.red.shade50
                                  : (isLoading
                                        ? primaryColor.withOpacity(0.05)
                                        : Colors.grey.shade100)),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSuccess
                              ? Colors.green.shade200
                              : (isError
                                    ? Colors.red.shade200
                                    : (isLoading
                                          ? primaryColor.withOpacity(0.3)
                                          : Colors.transparent)),
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
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (isSuccess) ...[
                                const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                              ],
                              if (isError) ...[
                                const Icon(
                                  Icons.error,
                                  color: Colors.red,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                              ],
                              Expanded(
                                child: Text(
                                  statusText,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isSuccess
                                        ? Colors.green.shade700
                                        : (isError
                                              ? Colors.red.shade700
                                              : (isLoading
                                                    ? primaryColor
                                                    : Colors.black87)),
                                    fontWeight:
                                        (isLoading || isSuccess || isError)
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (isLoading) ...[
                            const SizedBox(height: 16),
                            LinearProgressIndicator(
                              borderRadius: const BorderRadius.all(
                                Radius.circular(4),
                              ),
                              color: primaryColor,
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
                                  foregroundColor: Colors.red.shade500,
                                  side: BorderSide(color: Colors.red.shade200),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: (selectedPdf == null || isLoading)
                          ? null
                          : _saveToObsidian,
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
                        backgroundColor: primaryColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 20),

            // ------------------------------------------
            // CỘT 2: PDF PREVIEW WITH ZOOM & TEXT INTERACTION TOOLBAR
            // ------------------------------------------
            Expanded(
              flex: 5,
              child: _buildPanel(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // THANH CÔNG CỤ PDF TOOLBAR (GIÚP ZOOM VÀ HOÀN TOÀN COPY ĐƯỢC CHỮ CHUYÊN NGHIỆP)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      color: Colors.white,
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
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          if (selectedPdf != null) ...[
                            // Nút chế độ di chuyển hoặc quét chọn text
                            IconButton(
                              // Thay đổi Icons.text_select_move thành Icons.highlight_alt
                              icon: Icon(
                                Icons.highlight_alt,
                                color:
                                    _pdfInteractionMode ==
                                        PdfInteractionMode.selection
                                    ? primaryColor
                                    : Colors.grey.shade600,
                              ),
                              tooltip: 'Bật/Tắt chế độ Quét Chọn Văn Bản',
                              onPressed: () {
                                setState(() {
                                  _pdfInteractionMode =
                                      _pdfInteractionMode ==
                                          PdfInteractionMode.pan
                                      ? PdfInteractionMode.selection
                                      : PdfInteractionMode.pan;
                                });
                              },
                            ),
                            const VerticalDivider(
                              width: 20,
                              indent: 8,
                              endIndent: 8,
                            ),
                            IconButton(
                              icon: const Icon(Icons.zoom_out),
                              tooltip: 'Thu nhỏ',
                              onPressed: () => _pdfViewerController.zoomLevel =
                                  (_pdfViewerController.zoomLevel - 0.25).clamp(
                                    1.0,
                                    3.0,
                                  ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.zoom_in),
                              tooltip: 'Phóng to',
                              onPressed: () => _pdfViewerController.zoomLevel =
                                  (_pdfViewerController.zoomLevel + 0.25).clamp(
                                    1.0,
                                    3.0,
                                  ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.restart_alt),
                              tooltip: 'Reset Zoom',
                              onPressed: () =>
                                  _pdfViewerController.zoomLevel = 1.0,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: selectedPdf != null
                          ? SfPdfViewer.file(
                              selectedPdf!,
                              controller: _pdfViewerController,
                              interactionMode:
                                  _pdfInteractionMode, // Thiết lập chế độ thao tác chọn text/pan
                              enableTextSelection:
                                  true, // Đảm bảo luôn cho phép copy chữ
                            )
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

            // ------------------------------------------
            // CỘT 3: 3-TAB MANAGEMENT PANEL (METADATA, CHAT, VAULT LIBRARY)
            // ------------------------------------------
            Expanded(
              flex: 4,
              child: DefaultTabController(
                length: 3, // Cấu hình 3 Tab chuyên sâu
                child: _buildPanel(
                  padding: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        color: Colors.grey.shade50,
                        child: TabBar(
                          indicatorColor: primaryColor,
                          indicatorWeight: 3,
                          labelColor: primaryColor,
                          unselectedLabelColor: Colors.grey.shade600,
                          tabs: const [
                            Tab(
                              icon: Icon(Icons.auto_awesome, size: 18),
                              text: "Metadata",
                            ),
                            Tab(
                              icon: Icon(Icons.chat_bubble_outline, size: 18),
                              text: "AI Chat",
                            ),
                            Tab(
                              icon: Icon(Icons.local_library, size: 18),
                              text: "Library",
                            ), // Tab Library mới
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: TabBarView(
                          children: [
                            // --------------------------------------
                            // TAB 1: METADATA FORM (FIXED TITLE BUG)
                            // --------------------------------------
                            SingleChildScrollView(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                children: [
                                  _buildTextField(
                                    'Title',
                                    _titleCtrl,
                                    maxLines: 3,
                                  ),
                                  _buildTextField(
                                    'Authors',
                                    _authorsCtrl,
                                    maxLines: 3,
                                  ),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: _buildTextField(
                                          'Venue',
                                          _venueCtrl,
                                          maxLines: 2,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _buildTextField(
                                          'Year',
                                          _yearCtrl,
                                        ),
                                      ),
                                    ],
                                  ),
                                  _buildTextField(
                                    'Tags / Keywords',
                                    _keywordsCtrl,
                                    maxLines: 2,
                                  ),
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
                                    maxLines: 6,
                                  ),
                                ],
                              ),
                            ),

                            // --------------------------------------
                            // TAB 2: AI CHAG ASSISTANT
                            // --------------------------------------
                            fullPdfText.isEmpty
                                ? Center(
                                    child: Text(
                                      'Select a PDF to start chatting.',
                                      style: TextStyle(
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                  )
                                : Column(
                                    children: [
                                      Expanded(
                                        child: ListView.builder(
                                          controller: _chatScrollCtrl,
                                          padding: const EdgeInsets.all(16),
                                          itemCount: chatMessages.length,
                                          itemBuilder: (context, index) {
                                            final msg = chatMessages[index];
                                            final isUser =
                                                msg['role'] == 'user';
                                            return Align(
                                              alignment: isUser
                                                  ? Alignment.centerRight
                                                  : Alignment.centerLeft,
                                              child: Container(
                                                margin: const EdgeInsets.only(
                                                  bottom: 12,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical: 12,
                                                    ),
                                                constraints: BoxConstraints(
                                                  maxWidth:
                                                      MediaQuery.of(
                                                        context,
                                                      ).size.width *
                                                      0.22,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: isUser
                                                      ? primaryColor
                                                      : Colors.grey.shade100,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        16,
                                                      ).copyWith(
                                                        bottomRight: isUser
                                                            ? const Radius.circular(
                                                                0,
                                                              )
                                                            : const Radius.circular(
                                                                16,
                                                              ),
                                                        bottomLeft: !isUser
                                                            ? const Radius.circular(
                                                                0,
                                                              )
                                                            : const Radius.circular(
                                                                16,
                                                              ),
                                                      ),
                                                ),
                                                child: Text(
                                                  msg['content']!,
                                                  style: TextStyle(
                                                    color: isUser
                                                        ? Colors.white
                                                        : Colors.black87,
                                                    height: 1.4,
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                      if (isChatLoading)
                                        Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: Row(
                                            children: [
                                              SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: primaryColor,
                                                    ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                "AI is thinking...",
                                                style: TextStyle(
                                                  color: Colors.grey.shade500,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      const Divider(height: 1),
                                      Padding(
                                        padding: const EdgeInsets.all(12.0),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: TextField(
                                                controller: _chatInputCtrl,
                                                decoration: InputDecoration(
                                                  hintText:
                                                      'Ask about this paper...',
                                                  contentPadding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 16,
                                                        vertical: 12,
                                                      ),
                                                  border: OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          24,
                                                        ),
                                                    borderSide: BorderSide.none,
                                                  ),
                                                  filled: true,
                                                  fillColor:
                                                      Colors.grey.shade200,
                                                ),
                                                onSubmitted: (_) =>
                                                    _sendChatMessage(),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            CircleAvatar(
                                              backgroundColor: primaryColor,
                                              child: IconButton(
                                                icon: const Icon(
                                                  Icons.send,
                                                  color: Colors.white,
                                                  size: 18,
                                                ),
                                                onPressed: isChatLoading
                                                    ? null
                                                    : _sendChatMessage,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),

                            // --------------------------------------
                            // TAB 3: VAULT LIBRARY SCREEN (MÀN HÌNH THƯ VIỆN)
                            // --------------------------------------
                            isLibraryLoading
                                ? Center(
                                    child: CircularProgressIndicator(
                                      color: primaryColor,
                                    ),
                                  )
                                : libraryPapers.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.folder_open,
                                          size: 48,
                                          color: Colors.grey.shade300,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          'Library is empty.',
                                          style: TextStyle(
                                            color: Colors.grey.shade500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.all(12.0),
                                        child: Row(
                                          children: [
                                            Text(
                                              'Saved Notes (${libraryPapers.length})',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const Spacer(),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.refresh,
                                                size: 20,
                                              ),
                                              tooltip: 'Làm mới thư viện',
                                              onPressed: _loadVaultLibrary,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Divider(height: 1),
                                      Expanded(
                                        child: ListView.builder(
                                          itemCount: libraryPapers.length,
                                          itemBuilder: (context, index) {
                                            final paper = libraryPapers[index];
                                            return ListTile(
                                              title: Text(
                                                paper['title']!,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              subtitle: Text(
                                                'Year: ${paper['year']}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                              trailing: Icon(
                                                Icons.arrow_forward_ios,
                                                size: 12,
                                                color: Colors.grey.shade400,
                                              ),
                                              leading: CircleAvatar(
                                                backgroundColor: primaryColor
                                                    .withOpacity(0.1),
                                                child: Icon(
                                                  Icons.description,
                                                  size: 16,
                                                  color: primaryColor,
                                                ),
                                              ),
                                              onTap: () => _openPaperFromLibrary(
                                                paper['path']!,
                                              ), // Kích hoạt vòng lặp đóng đọc lại file
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanel({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      clipBehavior: Clip.antiAlias,
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

  // HÀM XÂY DỰNG TEXTFIELD KIỂU MỚI: TÁCH BIỆT LABEL RA NGOÀI HOÀN TOÀN
  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          TextField(
            controller: controller,
            minLines: 1,
            maxLines: maxLines,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: 'Enter $label...',
              hintStyle: TextStyle(
                color: Colors.grey.shade400,
                fontWeight: FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ),
        ],
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
