# API Implementation Reference

This document provides complete code examples for each API integration.

## ResearchApiService Class Overview

Located in: `lib/services/api_service.dart`

All methods are well-documented with error handling.

---

## 1. Grobid PDF Processing

### processPdfWithGrobid()

**Purpose:** Send PDF to Grobid server for structured TEI XML extraction

**Signature:**
```dart
Future<String> processPdfWithGrobid(File pdfFile)
```

**Parameters:**
- `pdfFile`: File object pointing to the PDF

**Returns:** XML string (TEI format)

**Throws:**
- `SocketException`: If Grobid server unavailable
- `Exception`: If processing fails

**Usage Example:**
```dart
import 'dart:io';
import 'services/api_service.dart';

// Initialize service
final service = ResearchApiService(
  grobidUrl: 'http://localhost:8070',
);

// Process PDF
try {
  final pdfFile = File('path/to/paper.pdf');
  final xmlResult = await service.processPdfWithGrobid(pdfFile);
  
  print('XML Result length: ${xmlResult.length}');
  // Sample output: '<?xml version="1.0"?>...[TEI XML]...'
  
} on SocketException catch (e) {
  print('Grobid not running: $e');
  print('Start it with: docker-compose up -d grobid');
} catch (e) {
  print('Processing error: $e');
}
```

**What happens internally:**
1. Creates multipart HTTP request
2. Adds PDF file to request
3. Sends to `http://localhost:8070/api/processFulltextDocument`
4. Returns response body as XML string
5. Includes 120-second timeout

**Advanced usage with timeout:**
```dart
// The method already has 120-second timeout
// For custom timeout, use http.Client directly:
final client = http.Client();
final request = http.MultipartRequest(
  'POST',
  Uri.parse('http://localhost:8070/api/processFulltextDocument'),
);
request.files.add(await http.MultipartFile.fromPath('pdf', pdfFile.path));

try {
  final streamedResponse = await client.send(request).timeout(
    const Duration(minutes: 3),  // Custom timeout
  );
  // ... handle response
} finally {
  client.close();
}
```

---

### parseGrobidXml()

**Purpose:** Parse Grobid TEI XML output into usable metadata

**Signature:**
```dart
static Map<String, dynamic> parseGrobidXml(String xmlString)
```

**Parameters:**
- `xmlString`: Raw XML output from Grobid

**Returns:** Map with keys:
```dart
{
  'title': String,
  'authors': String,      // Semicolon-separated
  'abstract': String,
  'keywords': String,     // Comma-separated
  'year': String,
  'error'?: String        // Only if parsing failed
}
```

**Usage Example:**
```dart
import 'services/api_service.dart';

final xmlString = '''<?xml version="1.0"?>
<TEI>
  <titleStmt>
    <title>Machine Learning Paper</title>
  </titleStmt>
  <fileDesc>
    <author>
      <persName>
        <forename>John</forename>
        <surname>Doe</surname>
      </persName>
    </author>
  </fileDesc>
</TEI>''';

final metadata = ResearchApiService.parseGrobidXml(xmlString);
print('Title: ${metadata['title']}');
print('Authors: ${metadata['authors']}');
print('Year: ${metadata['year']}');

// Output:
// Title: Machine Learning Paper
// Authors: Doe, John
// Year: Not Given
```

**Parsing logic:**
- Uses `package:xml` for DOM parsing
- Searches for specific TEI elements
- Returns 'Not Given' for missing fields
- Handles malformed XML gracefully

**Element mapping:**
| Field | XML Path | XPath |
|-------|----------|-------|
| title | titleStmt/title | `.findAllElements('title')` |
| author | author/persName | `.findElements('author')` |
| abstract | abstract | `.findAllElements('abstract')` |
| keyword | term | `.findAllElements('term')` |
| year | imprint/date[@when] | `.getAttribute('when')` |

---

## 2. OpenAlex Metadata Retrieval

### fetchOpenAlexMetadata()

**Purpose:** Query OpenAlex API for standardized research paper metadata

**Signature:**
```dart
Future<Map<String, dynamic>> fetchOpenAlexMetadata(String title)
```

**Parameters:**
- `title`: Paper title to search for (string)

**Returns:** Map with keys:
```dart
{
  'title': String,
  'authors': String,      // Comma-separated
  'year': String,
  'doi': String,          // DOI without 'https://doi.org/' prefix
  'venue': String,        // Journal/conference name
  'citedByCount': String, // Citation count as string
  'openalex_id': String,  // OpenAlex work ID
}
// Returns empty {} if no results found
```

**Usage Example:**
```dart
import 'services/api_service.dart';

final service = ResearchApiService();

try {
  // Search for paper by title
  final metadata = await service.fetchOpenAlexMetadata(
    'Deep Learning for Computer Vision'
  );
  
  if (metadata.isEmpty) {
    print('Paper not found in OpenAlex');
    return;
  }
  
  print('Title: ${metadata['title']}');
  print('Authors: ${metadata['authors']}');
  print('Year: ${metadata['year']}');
  print('DOI: ${metadata['doi']}');
  print('Venue: ${metadata['venue']}');
  print('Citations: ${metadata['citedByCount']}');
  
} catch (e) {
  print('Error: $e');
  // Graceful fallback to other metadata sources
}
```

**Advanced: Using partial matches**
```dart
// OpenAlex fuzzy matches, so you can use partial titles
await service.fetchOpenAlexMetadata('ResNet Deep Learning');
// Will find papers even if exact title doesn't match

// Tips for better results:
// 1. Use the most distinctive words from title
// 2. Avoid overly short titles
// 3. Include year if known for disambiguation
```

**Error handling:**
```dart
try {
  final metadata = await service.fetchOpenAlexMetadata(title);
} on SocketException {
  print('Network error - check internet connection');
} catch (e) {
  if (e.toString().contains('rate limit')) {
    print('Rate limited - try again in 1 minute');
  } else {
    print('API error: $e');
  }
}
```

**Rate limiting info:**
- Free OpenAlex API has generous limits
- Rate limit: ~10 requests per second per IP
- Very unlikely to hit in normal usage
- If hit: Wait 1 minute before retrying

**API endpoint details:**
```
GET https://api.openalex.org/works?search=<title>&per-page=1
```

**Response structure (before parsing):**
```json
{
  "results": [
    {
      "id": "https://openalex.org/W1234567890",
      "title": "Deep Learning for Computer Vision",
      "doi": "https://doi.org/10.1234/example.doi",
      "publication_date": "2023-06-15",
      "authorships": [
        {
          "author": {
            "id": "https://openalex.org/A1234567890",
            "display_name": "John Doe"
          }
        }
      ],
      "primary_location": {
        "source": {
          "id": "https://openalex.org/S1234567890",
          "display_name": "Nature",
          "issn_l": "0028-0836"
        }
      },
      "cited_by_count": 42,
      "type": "journal-article"
    }
  ]
}
```

---

## 3. Ollama Summary Generation

### generateSummaryWithOllama()

**Purpose:** Generate concise paper summary using local LLM

**Signature:**
```dart
Future<String> generateSummaryWithOllama(
  String pdfText, {
  String model = 'qwen2.5:14b',
  double temperature = 0.3,
})
```

**Parameters:**
- `pdfText`: Extracted PDF text (up to full PDF or limited to ~3000 chars)
- `model`: (Optional) LLM model name. Default: `'qwen2.5:14b'`
- `temperature`: (Optional) Creativity/determinism. Default: `0.3`
  - 0.0 = Most deterministic
  - 0.3 = Balanced (good for summaries)
  - 1.0+ = Most creative

**Returns:** Summary string

**Usage Example:**
```dart
import 'services/api_service.dart';

final service = ResearchApiService(
  ollamaUrl: 'http://localhost:11434',
);

try {
  final pdfText = '...full extracted PDF text...';
  
  // Generate summary with default settings
  final summary = await service.generateSummaryWithOllama(pdfText);
  print('Summary: $summary');
  
} on SocketException {
  print('Ollama not running');
  print('Start with: ollama serve');
  print('Then ensure model exists: ollama pull qwen2.5:14b');
} catch (e) {
  print('Error generating summary: $e');
}
```

**Using different models:**
```dart
// Fast summary (mistral model)
final fastSummary = await service.generateSummaryWithOllama(
  pdfText,
  model: 'mistral',  // Faster, decent quality
);

// Higher quality (neural-chat model)
final qualitySummary = await service.generateSummaryWithOllama(
  pdfText,
  model: 'neural-chat',
);

// Custom model
final customSummary = await service.generateSummaryWithOllama(
  pdfText,
  model: 'llama2',
);
```

**Adjusting temperature:**
```dart
// More focused, less creative (good for academic)
final focused = await service.generateSummaryWithOllama(
  pdfText,
  temperature: 0.1,  // Very focused
);

// More creative, longer summaries
final creative = await service.generateSummaryWithOllama(
  pdfText,
  temperature: 0.7,  // More creative
);
```

**Handling long texts:**
```dart
// The method automatically limits text to ~3000 chars
String limitedText = pdfText.length > 3000
    ? pdfText.substring(0, 3000) + '...'
    : pdfText;

// For longer texts, you could:
// 1. Extract just the abstract and introduction
// 2. Split text and summarize sections separately
// 3. Use abstractive summarization instead

// Example: Extract first 5 pages only
final firstPages = pdfText.split('\n').take(500).join('\n');
final summary = await service.generateSummaryWithOllama(firstPages);
```

**Prompt template (internal):**
```
System:
You are a research assistant. Provide a concise 2-3 sentence summary 
of the paper in English. Be specific about the main contribution.

User:
Summarize this paper: [PDF_TEXT]
```

**Expected output format:**
```
"This paper presents a deep learning framework for computer vision tasks.
The authors propose a novel CNN architecture that improves accuracy on 
ImageNet. Results show 3% improvement over previous state-of-the-art."
```

---

## 4. Ollama RAG Chat

### chatWithPaperContext()

**Purpose:** Chat with an LLM using paper text as context (RAG)

**Signature:**
```dart
Future<String> chatWithPaperContext(
  String userQuestion,
  String pdfContext, {
  String model = 'qwen2.5:14b',
  double temperature = 0.5,
})
```

**Parameters:**
- `userQuestion`: User's question about the paper
- `pdfContext`: Full extracted PDF text (used as context)
- `model`: (Optional) LLM model. Default: `'qwen2.5:14b'`
- `temperature`: (Optional) Default: `0.5`

**Returns:** LLM response string

**Usage Example:**
```dart
import 'services/api_service.dart';

final service = ResearchApiService();

try {
  final response = await service.chatWithPaperContext(
    'What is the main contribution of this paper?',
    pdfText,
  );
  print('AI: $response');
  
} catch (e) {
  print('Chat error: $e');
}
```

**Multi-turn conversation:**
```dart
// Store conversation history
List<Map<String, String>> conversation = [];

// First question
var response1 = await service.chatWithPaperContext(
  'What is the methodology?',
  pdfText,
);
conversation.add({'user': 'What is the methodology?', 'ai': response1});

// Follow-up question (context is maintained through pdfText)
var response2 = await service.chatWithPaperContext(
  'How does it compare to previous work?',
  pdfText,
);
conversation.add({'user': 'How does it compare to previous work?', 'ai': response2});
```

**Example questions:**
```dart
// Technical questions
await service.chatWithPaperContext(
  'Explain the algorithm in detail',
  pdfText,
);

// Methodology questions
await service.chatWithPaperContext(
  'What datasets were used for evaluation?',
  pdfText,
);

// Results questions
await service.chatWithPaperContext(
  'What were the main findings?',
  pdfText,
);

// Comparative questions
await service.chatWithPaperContext(
  'How does this work compare to [other paper]?',
  pdfText,
);

// Application questions
await service.chatWithPaperContext(
  'What are the practical applications of this work?',
  pdfText,
);
```

**Context limiting:**
```dart
// Automatically limits context to ~4000 chars to avoid token overflow
String limitedContext = pdfContext.length > 4000
    ? pdfContext.substring(0, 4000) + '...'
    : pdfContext;

// For more context, use a longer-context model
// or summarize the paper first
```

**Prompt template (internal):**
```
System:
You are an expert research assistant. Answer questions about the paper 
based on the provided context. Be precise and cite specific parts if relevant. 
Respond in English.

User:
Paper context:
[LIMITED_PDF_TEXT]

Question: [USER_QUESTION]
```

**Error handling:**
```dart
try {
  final answer = await service.chatWithPaperContext(
    question,
    context,
  );
  
  if (answer.contains('don\'t have')) {
    print('AI doesn\'t have information from paper context');
  }
  
} on SocketException {
  print('Ollama not running');
} catch (e) {
  print('Chat failed: $e');
}
```

---

## Complete Usage Example

Here's a complete example using all APIs together:

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'services/api_service.dart';

class PaperProcessingExample {
  final ResearchApiService service = ResearchApiService(
    grobidUrl: 'http://localhost:8070',
    ollamaUrl: 'http://localhost:11434',
  );

  Future<void> processPaperComplete(File pdfFile) async {
    try {
      // Step 1: Process with Grobid
      print('Processing PDF with Grobid...');
      final grobidXml = await service.processPdfWithGrobid(pdfFile);
      final grobidData = ResearchApiService.parseGrobidXml(grobidXml);
      print('Grobid title: ${grobidData['title']}');

      // Step 2: Query OpenAlex
      print('Querying OpenAlex...');
      final openalexData = await service.fetchOpenAlexMetadata(
        grobidData['title'] ?? '',
      );
      print('OpenAlex DOI: ${openalexData['doi']}');

      // Step 3: Extract full PDF text (simplified)
      String pdfText = 'Simulated extracted PDF text...';

      // Step 4: Generate summary
      print('Generating summary...');
      final summary = await service.generateSummaryWithOllama(pdfText);
      print('Summary: $summary');

      // Step 5: Chat with paper
      print('Starting RAG chat...');
      final chatResponse = await service.chatWithPaperContext(
        'What is the main contribution?',
        pdfText,
      );
      print('AI: $chatResponse');

      // Merge results
      final finalMetadata = {
        'title': openalexData['title'] ?? grobidData['title'],
        'authors': openalexData['authors'] ?? grobidData['authors'],
        'doi': openalexData['doi'],
        'year': openalexData['year'] ?? grobidData['year'],
        'venue': openalexData['venue'],
        'summary': summary,
      };

      print('\nFinal Metadata:');
      finalMetadata.forEach((key, value) {
        print('  $key: $value');
      });

    } catch (e) {
      print('Error: $e');
    }
  }
}
```

---

## Configuration Reference

```dart
// Initialize service with custom URLs
final service = ResearchApiService(
  grobidUrl: 'http://localhost:8070',      // Grobid server
  ollamaUrl: 'http://localhost:11434',     // Ollama server
  httpClient: http.Client(),                // Optional custom client
);

// Default configuration
const ResearchApiService(
  grobidUrl: 'http://localhost:8070',
  ollamaUrl: 'http://localhost:11434',
)
```

---

## Troubleshooting API Calls

### Test Connectivity

```bash
# Test Grobid
curl http://localhost:8070/api/isalive
# Expected: 1

# Test Ollama
curl http://localhost:11434/api/tags
# Expected: JSON with available models

# Test OpenAlex
curl 'https://api.openalex.org/works?search=machine%20learning&per-page=1'
# Expected: JSON with results
```

### Debug Requests

Add logging to see what's being sent:

```dart
import 'dart:io';

// Enable HTTP debugging
HttpOverrides.global = MyHttpOverrides();

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}
```

### Common Error Messages

| Error | Cause | Solution |
|-------|-------|----------|
| SocketException | Service not running | Start Grobid/Ollama |
| Timeout | Service too slow | Check server logs, increase timeout |
| rate limit exceeded | Too many requests | Wait 1 minute, retry |
| XML parse error | Malformed response | Try different PDF |
| No response from AI | Ollama overloaded | Restart Ollama |

---

## Performance Benchmarks

| Operation | Time | Notes |
|-----------|------|-------|
| `processPdfWithGrobid()` | 2-5 sec | PDF complexity dependent |
| `fetchOpenAlexMetadata()` | 1-2 sec | Network dependent |
| `generateSummaryWithOllama()` | 5-10 sec | Model size dependent |
| `chatWithPaperContext()` | 5-15 sec | Question complexity dependent |

---

**For more details, see:**
- API Service source: [lib/services/api_service.dart](lib/services/api_service.dart)
- Main integration: [lib/main.dart](lib/main.dart)
- Professional guide: [PROFESSIONAL_GUIDE.md](PROFESSIONAL_GUIDE.md)
