import http.server
import pathlib
import socketserver
import subprocess
import threading
import urllib.parse


PORT = 60323
MEDIA = pathlib.Path(
    r"C:\Users\ceo\Downloads\ytdlp-interface-gui-fresh-78e1af2d\server\input.mp4"
)
YTDLP = pathlib.Path(
    r"C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-final-candidates-5\candidate-55e66fa7d6004a0c84bce001c97d2c4d\yt-dlp.exe"
)


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, _format, *_args):
        return

    def send_bytes(self, data, content_type):
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        if path == "/master.m3u8":
            return self.send_bytes(
                (
                    "#EXTM3U\n"
                    '#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="Korean",'
                    'LANGUAGE="ko",AUTOSELECT=YES,DEFAULT=YES,URI="subs.m3u8"\n'
                    '#EXT-X-STREAM-INF:BANDWIDTH=800000,CODECS="avc1.4d401e,mp4a.40.2",'
                    'SUBTITLES="subs"\nvideo.m3u8\n'
                ).encode("utf-8"),
                "application/vnd.apple.mpegurl",
            )
        if path == "/video.m3u8":
            return self.send_bytes(
                b"#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:2\n#EXTINF:2.0,\nsegment.ts\n#EXT-X-ENDLIST\n",
                "application/vnd.apple.mpegurl",
            )
        if path == "/subs.m3u8":
            return self.send_bytes(
                b"#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:2\n#EXTINF:2.0,\nsubtitle.vtt\n#EXT-X-ENDLIST\n",
                "application/vnd.apple.mpegurl",
            )
        if path == "/subtitle.vtt":
            return self.send_bytes(
                "WEBVTT\n\n00:00.000 --> 00:01.500\n안녕하세요\n".encode("utf-8"),
                "text/vtt; charset=utf-8",
            )
        if path == "/segment.ts":
            return self.send_bytes(MEDIA.read_bytes(), "video/mp2t")
        self.send_response(404)
        self.end_headers()


server = socketserver.ThreadingTCPServer(("127.0.0.1", PORT), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    command = [str(YTDLP), "--no-warnings", "-J", f"http://127.0.0.1:{PORT}/master.m3u8"]
    result = subprocess.run(command, capture_output=True, text=True, timeout=30)
    print("COMMAND=" + " ".join(command))
    print(f"EXIT_CODE={result.returncode}")
    print("STDOUT_BEGIN")
    print(result.stdout)
    print("STDOUT_END")
    print("STDERR_BEGIN")
    print(result.stderr)
    print("STDERR_END")
finally:
    server.shutdown()
    server.server_close()
