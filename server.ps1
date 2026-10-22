param(
    [int]$Port = 3000
)

$baseDir = Join-Path $PSScriptRoot "puppy.instabizweb.com"
if (-not (Test-Path $baseDir)) {
    Write-Error "Target website directory not found: $baseDir"
    exit 1
}

$csharpCode = @"
using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Collections.Generic;

public class TeddyPupsServer {
    private readonly string _rootDir;
    private readonly int _port;
    private readonly List<string> _fallbackImages;
    private readonly Dictionary<string, string> _mimeTypes = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase) {
        { ".html", "text/html; charset=utf-8" },
        { ".htm", "text/html; charset=utf-8" },
        { ".css", "text/css; charset=utf-8" },
        { ".js", "application/javascript; charset=utf-8" },
        { ".mjs", "application/javascript; charset=utf-8" },
        { ".json", "application/json; charset=utf-8" },
        { ".svg", "image/svg+xml" },
        { ".png", "image/png" },
        { ".jpg", "image/jpeg" },
        { ".jpeg", "image/jpeg" },
        { ".webp", "image/webp" },
        { ".gif", "image/gif" },
        { ".woff2", "font/woff2" },
        { ".woff", "font/woff" },
        { ".ttf", "font/ttf" },
        { ".ico", "image/x-icon" },
        { ".txt", "text/plain; charset=utf-8" }
    };

    public TeddyPupsServer(string rootDir, int port) {
        _rootDir = Path.GetFullPath(rootDir);
        _port = port;

        _fallbackImages = new List<string>();
        string nextDir = Path.Combine(_rootDir, "_next");
        if (Directory.Exists(nextDir)) {
            foreach (var file in Directory.GetFiles(nextDir, "image*")) {
                _fallbackImages.Add(file);
            }
        }
    }

    public void Start() {
        TcpListener listener = new TcpListener(IPAddress.Loopback, _port);
        listener.Start();

        Console.ForegroundColor = ConsoleColor.Green;
        Console.WriteLine("==========================================================");
        Console.WriteLine("  TeddyPups website is RUNNING on Localhost!");
        Console.WriteLine("  Access URL: http://localhost:" + _port);
        Console.WriteLine("          or: http://127.0.0.1:" + _port);
        Console.WriteLine("  Press Ctrl+C to stop.");
        Console.WriteLine("==========================================================");
        Console.ResetColor();

        while (true) {
            try {
                TcpClient client = listener.AcceptTcpClient();
                ThreadPool.QueueUserWorkItem(new WaitCallback(ProcessClient), client);
            } catch (Exception ex) {
                Console.WriteLine("Accept error: " + ex.Message);
                break;
            }
        }
    }

    private void ProcessClient(object state) {
        TcpClient client = (TcpClient)state;
        try {
            client.NoDelay = true;
            client.ReceiveTimeout = 5000;
            client.SendTimeout = 5000;
            using (NetworkStream stream = client.GetStream()) {
                byte[] buffer = new byte[8192];
                int bytesRead = stream.Read(buffer, 0, buffer.Length);
                if (bytesRead <= 0) return;

                string requestText = Encoding.ASCII.GetString(buffer, 0, bytesRead);
                int firstLineEnd = requestText.IndexOf("\r\n");
                if (firstLineEnd < 0) firstLineEnd = requestText.IndexOf('\n');
                if (firstLineEnd < 0) return;

                string requestLine = requestText.Substring(0, firstLineEnd);
                string[] tokens = requestLine.Split(' ');
                if (tokens.Length < 2) return;

                string method = tokens[0].ToUpperInvariant();
                string fullUrl = tokens[1];

                if (method != "GET" && method != "HEAD") {
                    byte[] notAllowed = Encoding.UTF8.GetBytes("Method Not Allowed");
                    SendResponse(stream, 405, "Method Not Allowed", "text/plain", notAllowed);
                    return;
                }

                string pathOnly = fullUrl;
                string queryString = "";
                int qIndex = fullUrl.IndexOf('?');
                if (qIndex >= 0) {
                    pathOnly = fullUrl.Substring(0, qIndex);
                    queryString = fullUrl.Substring(qIndex + 1);
                }

                pathOnly = WebUtility.UrlDecode(pathOnly).Trim('/');

                // 1. Next.js image route: /_next/image?url=...
                if (pathOnly.Equals("_next/image", StringComparison.OrdinalIgnoreCase)) {
                    string targetImgUrl = GetQueryParam(queryString, "url");
                    if (!string.IsNullOrEmpty(targetImgUrl)) {
                        targetImgUrl = WebUtility.UrlDecode(targetImgUrl);
                        string localPath = Path.Combine(_rootDir, targetImgUrl.TrimStart('/', '\\').Replace('/', '\\'));

                        if (File.Exists(localPath)) {
                            ServeFile(stream, localPath);
                            return;
                        }

                        if (_fallbackImages.Count > 0) {
                            int hash = Math.Abs(targetImgUrl.GetHashCode()) % _fallbackImages.Count;
                            string fallbackPath = _fallbackImages[hash];
                            if (File.Exists(fallbackPath)) {
                                ServeFile(stream, fallbackPath);
                                return;
                            }
                        }
                    }
                }

                // 2. Normal static files
                if (string.IsNullOrEmpty(pathOnly) || pathOnly.Equals("index.html", StringComparison.OrdinalIgnoreCase)) {
                    pathOnly = "index.html";
                }

                string filePath = Path.Combine(_rootDir, pathOnly.Replace('/', '\\'));

                // SPA Fallback for routes like /puppies, /faq, etc.
                if (!File.Exists(filePath)) {
                    string ext = Path.GetExtension(pathOnly);
                    if (string.IsNullOrEmpty(ext)) {
                        filePath = Path.Combine(_rootDir, "index.html");
                    }
                }

                if (File.Exists(filePath)) {
                    ServeFile(stream, filePath);
                } else {
                    byte[] notFound = Encoding.UTF8.GetBytes("404 Not Found");
                    SendResponse(stream, 404, "Not Found", "text/plain", notFound);
                }
            }
        } catch {
            // Ignore connection aborts / resets
        } finally {
            try { client.Close(); } catch { }
        }
    }

    private void ServeFile(NetworkStream stream, string filePath) {
        byte[] bytes = File.ReadAllBytes(filePath);
        string ext = Path.GetExtension(filePath);
        string mime;

        if (bytes.Length >= 4 && bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46) {
            mime = "image/webp";
        } else if (bytes.Length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
            mime = "image/jpeg";
        } else if (bytes.Length >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
            mime = "image/png";
        } else if (!_mimeTypes.TryGetValue(ext, out mime)) {
            mime = "application/octet-stream";
        }

        SendResponse(stream, 200, "OK", mime, bytes);
    }

    private void SendResponse(NetworkStream stream, int statusCode, string statusMsg, string mime, byte[] body) {
        string headers = "HTTP/1.1 " + statusCode + " " + statusMsg + "\r\n" +
                         "Content-Type: " + mime + "\r\n" +
                         "Content-Length: " + body.Length + "\r\n" +
                         "Connection: close\r\n" +
                         "Cache-Control: public, max-age=31536000\r\n" +
                         "Access-Control-Allow-Origin: *\r\n\r\n";
        byte[] headerBytes = Encoding.ASCII.GetBytes(headers);
        stream.Write(headerBytes, 0, headerBytes.Length);

        int offset = 0;
        while (offset < body.Length) {
            int count = Math.Min(32768, body.Length - offset);
            stream.Write(body, offset, count);
            offset += count;
        }
        stream.Flush();
    }

    private string GetQueryParam(string queryString, string paramName) {
        if (string.IsNullOrEmpty(queryString)) return null;
        string[] pairs = queryString.Split('&');
        foreach (var pair in pairs) {
            string[] kv = pair.Split('=');
            if (kv.Length >= 2 && kv[0].Equals(paramName, StringComparison.OrdinalIgnoreCase)) {
                return kv[1];
            }
        }
        return null;
    }
}
"@

Add-Type -TypeDefinition $csharpCode
$server = New-Object TeddyPupsServer($baseDir, $Port)
$server.Start()
