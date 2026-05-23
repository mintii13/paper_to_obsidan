import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:xml/xml.dart' as xml;

/// ResearchApiService handles all external API integrations for research document processing
/// Supports: Grobid (PDF structure parsing), OpenAlex (metadata), Ollama (summaries & RAG)
class ResearchApiService {
  final String grobidUrl;
  final String ollamaUrl;
  final String? ollamaUsername;
  final String? ollamaPassword;
  final http.Client httpClient;

  ResearchApiService({
    this.grobidUrl = 'http://localhost:8070',
    this.ollamaUrl = 'http://109.237.69.169',
    this.ollamaUsername = 'mtn_ai',
    this.ollamaPassword = '130205',
    http.Client? httpClient,
  }) : httpClient = httpClient ?? http.Client();

  /// Helper method to create auth header for Ollama if credentials provided
  Map<String, String> _getOllamaHeaders() {
    final headers = {'Content-Type': 'application/json'};
    if (ollamaUsername != null && ollamaPassword != null) {
      final credentials = base64Encode(
        utf8.encode('$ollamaUsername:$ollamaPassword'),
      );
      headers['Authorization'] = 'Basic $credentials';
    }
    return headers;
  }

  // =========================================================================
  // 1. GROBID INTEGRATION - PDF Structure Parsing
  // =========================================================================

  /// Sends PDF to Grobid server and returns structured TEI XML
  /// Returns XML string containing metadata like title, authors, abstract
  /// Throws exception if Grobid service unavailable or processing fails
  Future<String> processPdfWithGrobid(File pdfFile) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$grobidUrl/api/processFulltextDocument'),
      );

      // Add PDF file to request using bytes (more reliable across platforms)
      final bytes = await pdfFile.readAsBytes();
      request.files.add(
        http.MultipartFile.fromBytes(
          'input',
          bytes,
          filename: pdfFile.uri.pathSegments.isNotEmpty
              ? pdfFile.uri.pathSegments.last
              : 'upload.pdf',
          contentType: MediaType('application', 'pdf'),
        ),
      );

      // Optional: Set processing options
      request.fields['consolidateHeader'] = '1';
      request.fields['consolidateMetadata'] = '1';

      final streamedResponse = await httpClient
          .send(request)
          .timeout(
            const Duration(seconds: 120),
            onTimeout: () => throw Exception(
              'Grobid processing timeout - server may be unavailable',
            ),
          );

      if (streamedResponse.statusCode == 200) {
        final responseBody = await streamedResponse.stream.bytesToString();
        return responseBody;
      } else {
        throw Exception(
          'Grobid error: ${streamedResponse.statusCode} - ${streamedResponse.reasonPhrase}',
        );
      }
    } on SocketException {
      throw Exception(
        'Cannot connect to Grobid server at $grobidUrl. '
        'Please ensure Grobid is running via Docker: docker-compose up grobid',
      );
    } catch (e) {
      throw Exception('Grobid processing failed: ${e.toString()}');
    }
  }

  // =========================================================================
  // 2. OPENIALEX INTEGRATION - Metadata Retrieval
  // =========================================================================

  /// Fetches standardized metadata from OpenAlex API using paper title
  /// Returns JSON containing DOI, year, authors, citation count, etc.
  /// Returns empty map if no results found
  Future<Map<String, dynamic>> fetchOpenAlexMetadata(String title) async {
    if (title.trim().isEmpty) {
      return {};
    }

    try {
      // OpenAlex API endpoint for works search
      final encodedTitle = Uri.encodeComponent(title);
      final url = Uri.parse(
        'https://api.openalex.org/works?search=$encodedTitle&per-page=1',
      );

      final response = await httpClient
          .get(url)
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw Exception('OpenAlex API timeout'),
          );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results'] as List?;

        if (results != null && results.isNotEmpty) {
          final work = results.first;
          return _parseOpenAlexWork(work);
        }
        return {}; // No results found
      } else if (response.statusCode == 429) {
        throw Exception(
          'OpenAlex rate limit exceeded. Please try again in a moment.',
        );
      } else {
        throw Exception('OpenAlex API error: ${response.statusCode}');
      }
    } on SocketException {
      throw Exception('Network error connecting to OpenAlex API');
    } catch (e) {
      throw Exception('OpenAlex metadata fetch failed: ${e.toString()}');
    }
  }

  /// Parses OpenAlex API response into standardized metadata format
  static Map<String, dynamic> _parseOpenAlexWork(Map<String, dynamic> work) {
    try {
      final authorsData = work['authorships'] as List? ?? [];
      final authors = authorsData
          .map((a) => (a['author']?['display_name'] ?? 'Unknown') as String)
          .join(', ');

      final publicationDate = work['publication_date'] as String?;
      final year = publicationDate?.split('-').first ?? '';

      return {
        'title': work['title'] ?? '',
        'authors': authors.isNotEmpty ? authors : 'Not Given',
        'year': year.isNotEmpty ? year : 'Not Given',
        'doi':
            work['doi']?.toString().replaceFirst('https://doi.org/', '') ??
            'Not Given',
        'venue':
            work['primary_location']?['source']?['display_name'] ??
            work['type'] ??
            'Not Given',
        'citedByCount': work['cited_by_count']?.toString() ?? '0',
        'openalex_id': work['id'] ?? '',
      };
    } catch (e) {
      return {'error': 'Failed to parse OpenAlex metadata: ${e.toString()}'};
    }
  }

  // =========================================================================
  // 3. OLLAMA INTEGRATION - Summarization & RAG Chat
  // =========================================================================

  /// Generates summary of paper using Ollama (llama2, qwen, etc.)
  /// Text should be extracted PDF content
  /// Returns summary string
  Future<String> generateSummaryWithOllama(
    String pdfText, {
    String model = 'qwen2.5:14b',
    double temperature = 0.3,
  }) async {
    if (pdfText.trim().isEmpty) {
      return 'Not Given';
    }

    try {
      // Limit text to avoid token overflow
      final limitedText = pdfText.length > 3000
          ? pdfText.substring(0, 3000) + '...'
          : pdfText;

      final response = await httpClient
          .post(
            Uri.parse('$ollamaUrl/api/chat'),
            headers: _getOllamaHeaders(),
            body: jsonEncode({
              'model': model,
              'messages': [
                {
                  'role': 'system',
                  'content':
                      'You are a research assistant. Provide a concise 2-3 sentence summary of the paper in English. Be specific about the main contribution.',
                },
                {
                  'role': 'user',
                  'content': 'Summarize this paper: $limitedText',
                },
              ],
              'format': 'json',
              'stream': false,
              'options': {'temperature': temperature},
            }),
          )
          .timeout(
            const Duration(seconds: 60),
            onTimeout: () => throw Exception('Ollama timeout'),
          );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final content = data['message']['content'];
        try {
          final summaryMap = jsonDecode(content);
          return summaryMap['summary'] ??
              content; // Dùng summary nếu có, không thì lấy nguyên văn
        } catch (e) {
          return content; // Nếu AI trả về text thường, cứ lấy text đó
        }
      } else {
        throw Exception('Ollama error: ${response.statusCode}');
      }
    } on SocketException {
      throw Exception(
        'Cannot connect to Ollama at $ollamaUrl. Ensure it is running.',
      );
    } catch (e) {
      throw Exception('Summary generation failed: ${e.toString()}');
    }
  }

  /// Chat with paper context using Ollama RAG
  /// Sends user question + paper text to LLM for context-aware response
  /// Returns response string
  Future<String> chatWithPaperContext(
    String userQuestion,
    String pdfContext, {
    String model = 'qwen2.5:14b',
    double temperature = 0.5,
  }) async {
    if (userQuestion.trim().isEmpty) {
      return 'Please ask a question.';
    }

    try {
      // Limit context to avoid token overflow
      final limitedContext = pdfContext.length > 4000
          ? pdfContext.substring(0, 4000) + '...'
          : pdfContext;

      final response = await httpClient
          .post(
            Uri.parse('$ollamaUrl/api/chat'),
            headers: _getOllamaHeaders(),
            body: jsonEncode({
              'model': model,
              'messages': [
                {
                  'role': 'system',
                  'content':
                      'You are an expert research assistant. Answer questions about the paper based on the provided context. Be precise and cite specific parts if relevant. Respond in English.',
                },
                {
                  'role': 'user',
                  'content':
                      'Paper context:\n$limitedContext\n\nQuestion: $userQuestion',
                },
              ],
              'stream': false,
              'options': {'temperature': temperature},
            }),
          )
          .timeout(
            const Duration(seconds: 60),
            onTimeout: () => throw Exception('Chat response timeout'),
          );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return data['message']['content'] ?? 'No response from AI';
      } else {
        throw Exception('Ollama error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Chat failed: ${e.toString()}');
    }
  }

  // =========================================================================
  // 4. GROBID XML PARSING UTILITIES
  // =========================================================================

  /// Extracts metadata from Grobid TEI XML response
  /// Returns map with: title, authors, abstract, keywords, year
  static Map<String, dynamic> parseGrobidXml(String xmlString) {
    try {
      final document = xml.XmlDocument.parse(xmlString);
      final root = document.rootElement;

      // Navigate through TEI XML structure
      String title = '';
      String authors = '';
      String abstract = '';
      String keywords = '';
      String year = '';

      // Extract title
      final titleElement = root.findAllElements('title').firstOrNull;
      title = titleElement?.text ?? '';

      // Extract authors (from bibl or analytic sections)
      final authorElements = root.findAllElements('author').toList();
      final authorNames = <String>[];

      for (var author in authorElements) {
        final persName = author.findElements('persName').firstOrNull;
        if (persName != null) {
          final forename =
              persName.findElements('forename').firstOrNull?.text ?? '';
          final surname =
              persName.findElements('surname').firstOrNull?.text ?? '';
          if (surname.isNotEmpty) {
            authorNames.add(
              '$surname${forename.isNotEmpty ? ', $forename' : ''}',
            );
          }
        }
      }
      authors = authorNames.join('; ');

      // Extract abstract
      final abstractElement = root.findAllElements('abstract').firstOrNull;
      abstract = abstractElement?.text ?? '';

      // Extract keywords
      final keywordElements = root.findAllElements('term').toList();
      keywords = keywordElements
          .map((e) => e.text)
          .where((k) => k.isNotEmpty)
          .join(', ');

      // Extract year from imprint/date
      final dateElement = root
          .findAllElements('imprint')
          .expand((e) => e.findAllElements('date'))
          .firstOrNull;
      // Extract citations
      final biblStructElements = root.findAllElements('biblStruct').toList();
      final citationsList = <String>[];
      for (var bibl in biblStructElements) {
        final analyticTitle = bibl.findElements('analytic').expand((e) => e.findElements('title')).firstOrNull?.text;
        final monogrTitle = bibl.findElements('monogr').expand((e) => e.findElements('title')).firstOrNull?.text;
        final citeTitle = analyticTitle ?? monogrTitle ?? '';
        
        // Skip if this citation title matches the main paper title
        if (citeTitle.isNotEmpty && title.isNotEmpty) {
          final citeLower = citeTitle.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
          final mainLower = title.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
          if (citeLower == mainLower || citeLower.contains(mainLower) || mainLower.contains(citeLower)) {
            continue;
          }
        }
        
        final authorsList = <String>[];
        final authorsNodes = bibl.findAllElements('author');
        for (var author in authorsNodes) {
          final surname = author.findAllElements('surname').firstOrNull?.text ?? '';
          if (surname.isNotEmpty) authorsList.add(surname);
        }
        
        if (citeTitle.isNotEmpty) {
          String cite = citeTitle;
          if (authorsList.isNotEmpty) cite = '${authorsList.join(', ')} - $citeTitle';
          citationsList.add(cite);
        }
      }

      return {
        'title': title.trim(),
        'authors': authors.isNotEmpty ? authors : 'Not Given',
        'abstract': abstract.isNotEmpty ? abstract : 'Not Given',
        'keywords': keywords.isNotEmpty ? keywords : 'Not Given',
        'year': year.isNotEmpty ? year : 'Not Given',
        'citations': citationsList,
      };
    } catch (e) {
      return {
        'error': 'Failed to parse Grobid XML: ${e.toString()}',
        'title': '',
        'authors': '',
        'abstract': '',
        'keywords': '',
        'year': '',
        'citations': <String>[],
      };
    }
  }
}
