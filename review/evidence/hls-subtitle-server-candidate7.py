import http.server
import pathlib
import socketserver
import sys
import urllib.parse

PORT = 60324
MEDIA = pathlib.Path(r"C:\Users\ceo\Downloads\ytdlp-interface-gui-fresh-78e1af2d\server\input.mp4")


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
            return self.send_bytes(("#EXTM3U\n"
                '#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="Korean",LANGUAGE="ko",AUTOSELECT=YES,DEFAULT=YES,URI="subs.m3u8"\n'
                '#EXT-X-STREAM-INF:BANDWIDTH=800000,CODECS="avc1.4d401e,mp4a.40.2",SUBTITLES="subs"\nvideo.m3u8\n').encode(), "application/vnd.apple.mpegurl")
        if path == "/video.m3u8":
            return self.send_bytes(b"#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:2\n#EXTINF:2.0,\nsegment.ts\n#EXT-X-ENDLIST\n", "application/vnd.apple.mpegurl")
        if path == "/subs.m3u8":
            return self.send_bytes(b"#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:2\n#EXTINF:2.0,\nsubtitle.vtt\n#EXT-X-ENDLIST\n", "application/vnd.apple.mpegurl")
        if path == "/subtitle.vtt":
            return self.send_bytes(b"WEBVTT\n\n00:00.000 --> 00:01.500\nKorean subtitle\n", "text/vtt; charset=utf-8")
        if path == "/segment.ts":
            return self.send_bytes(MEDIA.read_bytes(), "video/mp2t")
        self.send_response(404)
        self.end_headers()


with socketserver.ThreadingTCPServer(("127.0.0.1", PORT), Handler) as server:
    server.serve_forever()
