# Paper to Obsidian - Professional Architecture Guide

## Overview

This guide explains the upgraded architecture for professional scientific document management using Grobid, OpenAlex API, and Ollama.

## System Architecture

```
User selects PDF
       ↓
[Step 1] Extract PDF text (Syncfusion)
       ↓
[Step 2] Process with Grobid → Parse TEI XML
       ↓
[Step 3] Query OpenAlex with title → Get standardized metadata
       ↓
[Step 4] Generate summary with Ollama
       ↓
Populate metadata fields
       ↓
Enable RAG chat with paper context
```

## Services Workflow

### 1. **Grobid Integration** - PDF Structure Parsing

**What it does:**
- Parses PDF files to extract structured TEI XML
- Identifies title, authors, abstract, keywords from PDF
- Preserves document structure and formatting

**Location:** `lib/services/api_service.dart` → `processPdfWithGrobid()`

**Example usage:**
```dart
final grobidXml = await researchApiService.processPdfWithGrobid(pdfFile);
final metadata = ResearchApiService.parseGrobidXml(grobidXml);
// Returns: {title, authors, abstract, keywords, year}
```

**Docker setup:**
```bash
# Start Grobid
docker-compose up -d grobid

# Verify it's running
curl http://localhost:8070/api/isalive
# Expected: 1 (healthy)

# Stop Grobid
docker-compose down
```

### 2. **OpenAlex Integration** - Standardized Metadata

**What it does:**
- Searches for papers by title in OpenAlex
- Returns standardized, peer-reviewed metadata
- Includes DOI, citation count, publication venue, authors

**Location:** `lib/services/api_service.dart` → `fetchOpenAlexMetadata()`

**Example usage:**
```dart
final metadata = await researchApiService.fetchOpenAlexMetadata('Your Paper Title');
// Returns: {
//   title, authors, year, doi, venue, 
//   citedByCount, openalex_id
// }
```

**Important notes:**
- Free API, no authentication needed
- Rate limited but generous for normal use
- Works best with exact or similar paper titles
- Returns empty map if no matches found

### 3. **Ollama Integration** - Summary & RAG

**What it does:**
- Generates concise paper summaries
- Enables RAG (Retrieval-Augmented Generation) chat
- Provides context-aware responses using paper text

**Location:** `lib/services/api_service.dart`
- Summary: `generateSummaryWithOllama()`
- Chat: `chatWithPaperContext()`

**Example usage:**
```dart
// Generate summary
final summary = await researchApiService.generateSummaryWithOllama(pdfText);

// RAG chat
final response = await researchApiService.chatWithPaperContext(
  'What is the main contribution?',
  pdfText
);
```

**Setup:**
```bash
# Start Ollama (if not running)
ollama serve
# In another terminal
ollama pull qwen2.5:14b
```

---

## XML Parsing (Grobid Output)

Grobid returns TEI XML. Parsing example:

```dart
import 'package:xml/xml.dart' as xml;

Map<String, dynamic> parseGrobidXml(String xmlString) {
  final document = xml.XmlDocument.parse(xmlString);
  final root = document.rootElement;

  // Extract title
  final titleElement = root
      .findAllElements('titleStmt')
      .expand((e) => e.findAllElements('title'))
      .firstOrNull;
  final title = titleElement?.text ?? '';

  // Extract authors
  final authorElements = root.findAllElements('author').toList();
  final authors = authorElements
      .map((a) {
        final forename = a.findElements('forename').firstOrNull?.text ?? '';
        final surname = a.findElements('surname').firstOrNull?.text ?? '';
        return '$surname, $forename';
      })
      .join('; ');

  // Extract abstract
  final abstract = root.findAllElements('abstract').firstOrNull?.text ?? '';

  // Extract year from date element
  final year = root
      .findAllElements('imprint')
      .expand((e) => e.findAllElements('date'))
      .firstOrNull
      ?.getAttribute('when') ?? '';

  return {
    'title': title.trim(),
    'authors': authors,
    'abstract': abstract,
    'year': year,
  };
}
```

The `ResearchApiService` includes `parseGrobidXml()` as a static method.

---

## JSON Parsing (OpenAlex Output)

OpenAlex returns clean JSON. Example response structure:

```json
{
  "results": [
    {
      "title": "Paper Title",
      "id": "https://openalex.org/W...",
      "doi": "https://doi.org/10.xxxx/xxxxx",
      "publication_date": "2023-06-15",
      "authorships": [
        {
          "author": {
            "display_name": "John Smith",
            "id": "https://openalex.org/A..."
          }
        }
      ],
      "primary_location": {
        "source": {
          "display_name": "Nature"
        }
      },
      "cited_by_count": 42,
      "type": "journal-article"
    }
  ]
}
```

**Parsing code** (already implemented in `api_service.dart`):

```dart
static Map<String, dynamic> _parseOpenAlexWork(Map<String, dynamic> work) {
  // Extract authors
  final authors = (work['authorships'] as List?)
      ?.map((a) => a['author']?['display_name'] ?? 'Unknown')
      .join(', ')
      ?? '';

  // Extract year from publication date
  final year = (work['publication_date'] as String?)?.split('-').first ?? '';

  // Extract DOI
  final doi = work['doi']?.toString()
      .replaceFirst('https://doi.org/', '') ?? '';

  // Extract venue
  final venue = work['primary_location']?['source']?['display_name']
      ?? work['type'] ?? '';

  return {
    'title': work['title'] ?? '',
    'authors': authors,
    'year': year,
    'doi': doi,
    'venue': venue,
    'citedByCount': work['cited_by_count']?.toString() ?? '0',
  };
}
```

---

## Error Handling Strategy

All services include robust error handling:

### Grobid Errors
```dart
try {
  final xml = await researchApiService.processPdfWithGrobid(pdfFile);
} on SocketException {
  // Grobid not running
  showError('Ensure Grobid is running: docker-compose up -d grobid');
} catch (e) {
  // Processing error
  showError('PDF processing failed: $e');
}
```

### OpenAlex Errors
```dart
try {
  final metadata = await researchApiService.fetchOpenAlexMetadata(title);
  if (metadata.isEmpty) {
    // No match found - fall back to Grobid
  }
} catch (e) {
  // Network or API error - continue with Grobid data
  debugPrint('OpenAlex error: $e');
}
```

### Ollama Errors
```dart
try {
  final summary = await researchApiService.generateSummaryWithOllama(text);
} on SocketException {
  showError('Ensure Ollama is running: ollama serve');
} catch (e) {
  // Return default if timeout/error
  summary = 'Not Given';
}
```

**Graceful degradation:**
- If Grobid fails → fall back to Ollama extraction
- If OpenAlex fails → use Grobid data
- If Ollama fails → user can write summary manually

---

## Metadata Population Logic

Data priority (highest to lowest):

```
TITLE:      OpenAlex > Grobid
AUTHORS:    OpenAlex > Grobid  
YEAR:       OpenAlex > Grobid
VENUE:      OpenAlex (most reliable)
KEYWORDS:   Grobid extracted
ABSTRACT:   Grobid extracted
SUMMARY:    Ollama generated
DOI:        OpenAlex only
```

Implementation in `main.dart`:

```dart
void _populateMetadataFields(
  Map<String, dynamic> grobidData,
  Map<String, dynamic> openalexData,
  String summary,
) {
  setState(() {
    // Prefer OpenAlex, fall back to Grobid
    _titleCtrl.text = (openalexData['title'] as String?) ?? 
                      (grobidData['title'] as String?) ?? '';
    
    _authorsCtrl.text = (openalexData['authors'] as String?) ?? 
                        (grobidData['authors'] as String?) ?? '';
    
    // Use specialized sources
    _venueCtrl.text = (openalexData['venue'] as String?) ?? '';
    _keywordsCtrl.text = (grobidData['keywords'] as String?) ?? '';
    _summaryCtrl.text = summary;
  });
}
```

---

## RAG Chat Implementation

The RAG (Retrieval-Augmented Generation) chat uses paper context:

```dart
Future<String> chatWithPaperContext(
  String userQuestion,
  String pdfContext,
) async {
  // Limit context to ~4000 chars to avoid token overflow
  final limitedContext = pdfContext.length > 4000
      ? pdfContext.substring(0, 4000) + '...'
      : pdfContext;

  final response = await httpClient.post(
    Uri.parse('$ollamaUrl/api/chat'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'model': 'qwen2.5:14b',
      'messages': [
        {
          'role': 'system',
          'content':
              'You are an expert research assistant. Answer based on the paper context. '
              'If the answer is not in the context, say you don\'t know.',
        },
        {
          'role': 'user',
          'content': 'Paper context:\n$limitedContext\n\nQuestion: $userQuestion',
        },
      ],
      'stream': false,
      'options': {'temperature': 0.5},
    }),
  );

  return data['message']['content'];
}
```

**Features:**
- Context-aware responses using paper text
- Limits context to avoid token overflow
- Maintains temperature=0.5 for balance of creativity/accuracy
- Structured prompts for better outputs

---

## Configuration & Environment Variables

### Docker Grobid (port 8070)
```yaml
# docker-compose.yml
services:
  grobid:
    image: grobid/grobid:latest
    ports:
      - "8070:8070"
    environment:
      - JAVA_OPTS=-Xmx4g  # Allocate 4GB RAM
```

### Ollama (port 11434)
```bash
# Terminal 1: Start Ollama
ollama serve

# Terminal 2: Ensure model is available
ollama pull qwen2.5:14b
```

### Flutter App Configuration
```dart
final researchApiService = ResearchApiService(
  grobidUrl: 'http://localhost:8070',    // Grobid server
  ollamaUrl: 'http://localhost:11434',   // Ollama server
  httpClient: http.Client(),              // Optional custom client
);
```

---

## Testing the Complete Flow

### 1. Start Services
```bash
# Terminal 1: Start Grobid
docker-compose up grobid

# Terminal 2: Start Ollama
ollama serve

# Terminal 3: Run Flutter app
flutter run -d windows
```

### 2. Verify Connectivity
```bash
# Check Grobid
curl http://localhost:8070/api/isalive
# Expected: 1

# Check Ollama
curl http://localhost:11434/api/tags
# Expected: JSON with models list
```

### 3. Upload PDF
- Click "Choose PDF" in app
- Select any research paper PDF
- App will:
  - Extract text
  - Send to Grobid (2-5 seconds)
  - Query OpenAlex (1-2 seconds)
  - Generate summary with Ollama (5-10 seconds)
  - Populate all fields

### 4. Verify Results
- Check metadata fields are populated
- Review accuracy of extracted data
- Test RAG chat with questions about the paper

---

## Troubleshooting

### "Cannot connect to Grobid"
```bash
# Check if running
docker-compose ps

# Start if not running
docker-compose up -d grobid

# Check logs
docker-compose logs grobid
```

### "OpenAlex rate limit exceeded"
- Normal API has generous rate limits
- Wait a moment and retry
- For production, consider upgrading to institutional access

### "Ollama timeout"
```bash
# Check if Ollama is running
curl http://localhost:11434/api/tags

# Ensure model is loaded
ollama pull qwen2.5:14b

# If slow, try smaller model
ollama pull mistral  # Smaller, faster
```

### "XML parsing error"
- May be malformed PDF or Grobid processing issue
- Check Grobid logs for details
- Falls back to Ollama extraction automatically

---

## Dependencies Required

```yaml
# pubspec.yaml
dependencies:
  http: ^1.2.2        # API calls
  xml: ^6.5.0         # Parse Grobid TEI XML
  syncfusion_flutter_pdf: ^27.1.52  # PDF extraction
```

Install:
```bash
flutter pub get
```

---

## File Structure

```
lib/
├── main.dart                 # Updated with professional workflow
└── services/
    └── api_service.dart      # ResearchApiService (NEW)

root/
├── docker-compose.yml        # Grobid Docker config (NEW)
├── DOCKER_SETUP.md          # Docker instructions (NEW)
└── PROFESSIONAL_GUIDE.md    # This file
```

---

## Next Steps

1. ✅ Install `xml` package: `flutter pub get`
2. ✅ Start Docker Grobid: `docker-compose up -d grobid`
3. ✅ Start Ollama: `ollama serve` + `ollama pull qwen2.5:14b`
4. ✅ Run app: `flutter run -d windows`
5. Test with a research paper PDF
6. Customize metadata fields as needed for your workflow

---

## Performance Notes

**Processing times (typical):**
- PDF text extraction: 0.5-2 seconds
- Grobid processing: 2-5 seconds
- OpenAlex query: 1-2 seconds
- Ollama summary: 5-10 seconds
- **Total: 8-20 seconds**

**Optimization tips:**
- Use faster Ollama model for quicker summaries: `mistral`
- Reduce PDF pages limit if processing large files
- Use local network if Ollama on same machine
- Monitor Grobid memory usage in `docker-compose.yml`

---

**Last Updated:** May 2026  
**Architecture Version:** 2.0 (Professional)
