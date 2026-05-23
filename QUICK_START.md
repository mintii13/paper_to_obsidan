# Quick Start Guide - Professional Research Document Management

## ⚡ 30-Second Overview

Your Flutter app now has **professional-grade research document processing**:

- 📄 **Grobid**: Parses PDF structure to extract title, authors, abstract
- 🔍 **OpenAlex**: Fetches standardized metadata (DOI, citations, etc.)
- 🤖 **Ollama**: Generates summaries and enables RAG chat
- 🎯 **Smart merging**: Combines best data from all sources

---

## 🚀 Setup (5 minutes)

### Step 1: Install Dependencies
```bash
cd d:\FPTU-sourse\Term8\PRM393\checkpoint1\paper_to_obsidian
flutter pub get
```

### Step 2: Start Grobid (Docker)
```bash
# In your project root folder:
docker compose up -d grobid

# Verify it's running:
curl http://localhost:8070/api/isalive
# Expected response: 1
```

**Troubleshooting Grobid:**
- If port 8070 is in use: `netstat -ano | findstr :8070`
- Need more memory: Edit `docker-compose.yml`, change `JAVA_OPTS=-Xmx4g` to `-Xmx8g`
- View logs: `docker-compose logs -f grobid`

### Step 3: Start Ollama
```bash
# Terminal 1: Start Ollama service
ollama serve

# Terminal 2: Ensure model is loaded
ollama pull qwen2.5:14b
```

**Skip if Ollama already running:**
```bash
# Check if already running:
curl http://localhost:11434/api/tags
```

### Step 4: Run the App
```bash
flutter run -d windows
```

---

## 📋 How It Works

### Processing Flow
```
You select PDF
    ↓
Extract text (1 sec)
    ↓
Grobid parses PDF (3-5 sec) → Get title, authors, abstract
    ↓
OpenAlex queries with title (1-2 sec) → Get DOI, citations, venue
    ↓
Ollama generates summary (5-10 sec)
    ↓
All fields automatically filled ✓
    ↓
Chat with paper using RAG
```

### Example: Processing a paper
1. **Click "Choose PDF"** → Select a research paper
2. **App shows progress:**
   - "Step 1/4: Extracting text..."
   - "Step 2/4: Parsing PDF structure..."
   - "Step 3/4: Fetching standardized metadata..."
   - "Step 4/4: Generating summary..."
3. **Fields auto-populated:**
   - ✓ Title (from OpenAlex or Grobid)
   - ✓ Authors (from OpenAlex or Grobid)
   - ✓ Year (from OpenAlex or Grobid)
   - ✓ Venue/Journal (from OpenAlex)
   - ✓ Keywords (from Grobid)
   - ✓ Summary (from Ollama)
4. **Ask questions** → "What's the main contribution?" → Ollama answers using paper context

---

## 🔧 API Integration Details

### 1. Grobid (Local Docker)
- **URL:** http://localhost:8070
- **What it does:** Parses PDF files, extracts TEI XML with structured metadata
- **Input:** PDF file
- **Output:** XML string with title, authors, abstract, keywords

**Code in app:**
```dart
final xml = await researchApiService.processPdfWithGrobid(pdfFile);
final metadata = ResearchApiService.parseGrobidXml(xml);
// metadata contains: title, authors, abstract, year, keywords
```

### 2. OpenAlex (Free Cloud API)
- **URL:** https://api.openalex.org
- **What it does:** Searches for papers by title, returns standardized metadata
- **Input:** Paper title (string)
- **Output:** JSON with DOI, authors, year, citations, venue

**Code in app:**
```dart
final metadata = await researchApiService.fetchOpenAlexMetadata(title);
// metadata contains: title, authors, year, doi, venue, citedByCount
```

### 3. Ollama (Local LLM)
- **URL:** http://localhost:11434
- **Models:** qwen2.5:14b (default), mistral (faster)
- **What it does:** Generates summaries, answers questions with paper context

**Code in app:**
```dart
// Generate summary
final summary = await researchApiService.generateSummaryWithOllama(pdfText);

// Chat with context (RAG)
final answer = await researchApiService.chatWithPaperContext(
  'What is the main contribution?',
  pdfText
);
```

---

## 📚 File Structure (What Changed)

**NEW FILES:**
```
lib/services/api_service.dart          ← ResearchApiService class
docker-compose.yml                     ← Grobid Docker config
DOCKER_SETUP.md                        ← Docker instructions
PROFESSIONAL_GUIDE.md                  ← Detailed architecture guide
QUICK_START.md                         ← This file
```

**MODIFIED FILES:**
```
lib/main.dart                          ← Updated with new workflow
pubspec.yaml                           ← Added xml package
```

---

## ✅ Verify Everything Works

### Test 1: Check Grobid
```bash
curl http://localhost:8070/api/isalive
# Expected: 1
```

### Test 2: Check Ollama
```bash
curl http://localhost:11434/api/tags
# Expected: JSON with model list
```

### Test 3: Process a PDF
1. Run the app: `flutter run -d windows`
2. Click "Choose PDF"
3. Select any research paper PDF
4. Watch the progress (Step 1-4)
5. Verify metadata appears in the form
6. Ask a question in the chat

---

## 🆘 Common Issues & Solutions

### "Cannot connect to Grobid"
**Problem:** Status shows "Grobid processing failed"
```bash
# Solution 1: Start Grobid
docker-compose up -d grobid

# Solution 2: Check if it's running
docker ps | grep grobid

# Solution 3: View logs for errors
docker-compose logs grobid
```

### "Ollama timeout"
**Problem:** Summary generation takes forever or fails
```bash
# Solution 1: Check if Ollama is running
curl http://localhost:11434/api/tags

# Solution 2: Start Ollama if not running
ollama serve

# Solution 3: If too slow, use faster model
ollama pull mistral
# Then update app to use 'mistral' instead of 'qwen2.5:14b'
```

### "OpenAlex rate limit"
**Problem:** Error says "rate limit exceeded"
- **Solution:** Wait 1 minute and try again (very rare)
- OpenAlex has generous free limits

### "XML parsing error"
**Problem:** Error message contains "parse Grobid XML"
- **Cause:** PDF might be malformed or Grobid couldn't process it
- **Solution:** Try a different PDF
- **Fallback:** App automatically falls back to Ollama extraction

### Port Already in Use
**Problem:** Error says "port 8070 is already in use"
```bash
# Find what's using it
netstat -ano | findstr :8070

# Option 1: Kill the process
taskkill /PID <PID> /F

# Option 2: Use different port
# Edit docker-compose.yml, change "8070:8070" to "8071:8070"
```

---

## 🎯 Configuration Options

### Change Ollama Model
```dart
// In lib/main.dart, find _processWithGrobidAndOpenAlex()
// Change this line:
summary = await researchApiService.generateSummaryWithOllama(
  fullPdfText,
  model: 'mistral',  // ← Change here
);
```

Available models:
- `qwen2.5:14b` (default) - Best quality
- `mistral` - Faster, good quality
- `neural-chat` - Fast, decent quality

### Change Grobid/Ollama URLs
```dart
// In lib/main.dart, initState():
researchApiService = ResearchApiService(
  grobidUrl: 'http://YOUR_SERVER:8070',
  ollamaUrl: 'http://YOUR_SERVER:11434',
);
```

### Adjust Summary Temperature
```dart
// Lower = more focused/accurate, Higher = more creative
summary = await researchApiService.generateSummaryWithOllama(
  fullPdfText,
  temperature: 0.2,  // ← Change here (default: 0.3)
);
```

---

## 📖 Learn More

- **Architecture details:** See [PROFESSIONAL_GUIDE.md](PROFESSIONAL_GUIDE.md)
- **Docker setup:** See [DOCKER_SETUP.md](DOCKER_SETUP.md)
- **Source code:** See [lib/services/api_service.dart](lib/services/api_service.dart)
- **Main logic:** See [lib/main.dart](lib/main.dart#L247)

---

## 🔄 Processing Pipeline Details

### What Happens in Step 2 (Grobid)
```dart
// Grobid parses PDF and returns TEI XML
String grobidXml = await researchApiService.processPdfWithGrobid(selectedPdf!);

// Parse XML to extract metadata
Map<String, dynamic> grobidData = ResearchApiService.parseGrobidXml(grobidXml);
// Result example:
{
  'title': 'Deep Learning for Computer Vision',
  'authors': 'Smith, John; Doe, Jane',
  'abstract': 'This paper presents a comprehensive study of...',
  'keywords': 'deep learning, neural networks, vision',
  'year': '2023',
}
```

### What Happens in Step 3 (OpenAlex)
```dart
// Query OpenAlex with the title from Grobid
Map<String, dynamic> openalexData = 
  await researchApiService.fetchOpenAlexMetadata(grobidData['title']);
// Result example:
{
  'title': 'Deep Learning for Computer Vision',
  'authors': 'Smith, John, Doe, Jane',
  'year': '2023',
  'doi': '10.1234/example.doi',
  'venue': 'IEEE Transactions on Pattern Analysis and Machine Intelligence',
  'citedByCount': '42',
  'openalex_id': 'https://openalex.org/W...',
}
```

### What Happens in Step 4 (Ollama)
```dart
// Ollama generates a concise summary
String summary = await researchApiService.generateSummaryWithOllama(fullPdfText);
// Result example:
// "This paper presents a deep learning framework for computer vision tasks.
//  The authors propose a novel CNN architecture that achieves state-of-the-art
//  results on multiple benchmarks. The method addresses limitations of previous
//  approaches through improved feature extraction and training strategies."
```

### Data Merging Logic
```dart
// Priority: OpenAlex > Grobid > Default
_titleCtrl.text = 
  openalexData['title'] ??      // Try OpenAlex first
  grobidData['title'] ??        // Fall back to Grobid
  '';                           // Default empty

_authorsCtrl.text = 
  openalexData['authors'] ??    // OpenAlex has better author formatting
  grobidData['authors'] ?? '';

_yearCtrl.text = 
  openalexData['year'] ??
  grobidData['year'] ?? '';

_venueCtrl.text = 
  openalexData['venue'] ?? '';  // OpenAlex most reliable for venue

_summaryCtrl.text = summary;    // From Ollama only
```

---

## 🎓 How to Customize for Your Workflow

### Add More Fields
1. Add TextEditingController: `final _doiCtrl = TextEditingController();`
2. Add UI TextField in build()
3. Populate in `_populateMetadataFields()`: `_doiCtrl.text = openalexData['doi'] ?? '';`

### Change Processing Order
Edit `_processWithGrobidAndOpenAlex()` in lib/main.dart

### Skip OpenAlex (Grobid Only)
```dart
// Comment out OpenAlex call in _processWithGrobidAndOpenAlex()
// openalexData = await researchApiService.fetchOpenAlexMetadata(...);
openalexData = {}; // Use empty data
```

### Use Different Summary Model
```dart
// In _processWithGrobidAndOpenAlex():
summary = await researchApiService.generateSummaryWithOllama(
  fullPdfText,
  model: 'mistral',  // Faster, good quality
);
```

---

## 📊 Performance Expectations

| Step | Time | Notes |
|------|------|-------|
| Extract PDF text | 0.5-2 sec | Depends on PDF size |
| Grobid processing | 2-5 sec | May take longer for complex PDFs |
| OpenAlex query | 1-2 sec | Network dependent |
| Ollama summary | 5-10 sec | Slower models take longer |
| **Total** | **8-20 sec** | Typical processing time |

**Tips to speed up:**
- Use `mistral` model instead of `qwen2.5:14b`
- Run on same machine (lower latency)
- Use SSD for faster disk I/O
- Increase Grobid memory if available

---

## ✨ What's New vs. Old

### Before (Ollama-Only)
- PDF → Ollama extraction → Fields filled
- **Problem:** Ollama often missed metadata, inconsistent extraction

### After (Professional Multi-Source)
- PDF → Grobid (structure) → OpenAlex (standardization) → Ollama (summary)
- **Benefits:**
  - ✅ Accurate metadata from OpenAlex
  - ✅ Structured data from Grobid
  - ✅ Better summaries from Ollama
  - ✅ Graceful fallback if any service fails
  - ✅ Faster, more reliable extraction

---

## 🚀 Next Steps

1. ✅ **Now:** Follow Setup (5 minutes above)
2. **Test:** Upload a research paper and verify all fields populate
3. **Customize:** Add more metadata fields if needed
4. **Deploy:** Run on your machine, enjoy RAG chat!

---

**Need help?**
- Check [PROFESSIONAL_GUIDE.md](PROFESSIONAL_GUIDE.md) for architecture details
- Check [DOCKER_SETUP.md](DOCKER_SETUP.md) for Docker commands
- Review [lib/services/api_service.dart](lib/services/api_service.dart) for API implementation

**Happy researching! 📚**
