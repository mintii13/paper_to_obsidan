# Grobid Docker Setup Guide

## Prerequisites
- Docker Desktop installed and running
- docker-compose installed (comes with Docker Desktop)

## Quick Start

### 1. Start Grobid Service
Navigate to your project root and run:

```bash
docker-compose up -d grobid
```

The `-d` flag runs it in the background. Grobid will be available at `http://localhost:8070`

### 2. Verify Grobid is Running
Check if Grobid is healthy:

```bash
curl http://localhost:8070/api/isalive
```

Expected response: `1` (means healthy)

Alternatively, visit in browser: http://localhost:8070/api/isalive

### 3. View Logs
To see what Grobid is doing:

```bash
docker-compose logs -f grobid
```

Press `Ctrl+C` to stop viewing logs.

### 4. Stop Grobid
When you're done:

```bash
docker-compose down
```

This stops and removes the container (data is preserved in the volume).

## Troubleshooting

### Port 8070 Already in Use
```bash
# Find what's using port 8070
netstat -ano | findstr :8070

# If it's Docker, restart Docker Desktop
# If it's another service, kill it or use a different port in docker-compose.yml
```

### Grobid Not Responding
1. Check if container is running:
   ```bash
   docker-compose ps
   ```

2. Check logs for errors:
   ```bash
   docker-compose logs grobid
   ```

3. Make sure you have enough disk space and RAM
   - The `JAVA_OPTS=-Xmx4g` setting allocates 4GB RAM
   - Adjust this if your system has less memory available

### Permission Errors
- On Windows: Run PowerShell/CMD as Administrator
- On Linux/Mac: Use `sudo docker-compose up -d grobid`

## Integration with Flutter App

The Flutter app will automatically try to connect to Grobid at `http://localhost:8070` during PDF processing. Make sure:

1. Grobid is running before you process PDFs in the app
2. If you change the port in docker-compose.yml, update it in the Flutter code as well
