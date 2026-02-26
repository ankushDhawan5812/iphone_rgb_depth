#!/usr/bin/env python3
"""
RGB + Depth Receiver
Receives JPEG/H.264 RGB and PNG depth streams from iPhone
"""

import socket
import struct
import json
import cv2
import numpy as np
from datetime import datetime
import subprocess
import threading

# Frame types
FRAME_TYPE_RGB = 0x01
FRAME_TYPE_DEPTH = 0x02
FRAME_TYPE_METADATA = 0x03

# Header format: type(1) + timestamp(8) + frame_num(4) + data_size(4) + is_key(1) = 18 bytes
HEADER_SIZE = 18
HEADER_FORMAT = '<BdIIB'  # Little-endian: byte, double, uint, uint, byte (iOS uses little-endian)

class FrameReceiver:
    def __init__(self, host='0.0.0.0', port=8888):
        self.host = host
        self.port = port
        self.server_socket = None
        self.client_socket = None
        self.metadata = None
        self.rgb_encoding = 'h264'

        # Stats
        self.frames_received = {'rgb': 0, 'depth': 0}
        self.bytes_received = {'rgb': 0, 'depth': 0}
        self.start_time = None

        # For H.264 decoding
        self.h264_pipe = None
        self.decoder_thread = None
        self.latest_rgb_frame = None
        self.rgb_lock = threading.Lock()

        # For depth
        self.latest_depth_frame = None
        self.depth_lock = threading.Lock()

    def start(self):
        """Start TCP server"""
        self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server_socket.bind((self.host, self.port))
        self.server_socket.listen(1)

        print(f"🎧 Server listening on {self.host}:{self.port}")
        print(f"📱 Waiting for iPhone connection...")

        self.client_socket, addr = self.server_socket.accept()
        self.client_socket.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        print(f"✅ Connected to {addr}")

        self.start_time = datetime.now()

    def start_h264_decoder(self):
        """Start FFmpeg process for H.264 decoding"""
        ffmpeg_cmd = [
            'ffmpeg',
            '-f', 'h264',
            '-i', 'pipe:0',
            '-f', 'rawvideo',
            '-pix_fmt', 'bgr24',
            'pipe:1'
        ]

        try:
            self.h264_pipe = subprocess.Popen(
                ffmpeg_cmd,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                bufsize=10**8
            )
        except FileNotFoundError:
            print("❌ FFmpeg not found. Cannot decode H.264 RGB stream.")
            self.h264_pipe = None
            return False

        # Start thread to read decoded frames
        self.decoder_thread = threading.Thread(target=self._decode_h264_frames, daemon=True)
        self.decoder_thread.start()
        return True

    def _decode_h264_frames(self):
        """Background thread to decode H.264 frames"""
        if self.metadata is None:
            print("⚠️ Decoder thread started but no metadata yet")
            return

        width = self.metadata.get('rgbWidth', 1920)
        height = self.metadata.get('rgbHeight', 1440)
        frame_size = width * height * 3  # BGR24

        print(f"🎬 Decoder thread running: expecting {width}x{height} frames ({frame_size} bytes each)")

        frame_count = 0
        while True:
            try:
                raw_frame = self.h264_pipe.stdout.read(frame_size)
                if len(raw_frame) != frame_size:
                    print(f"⚠️ Decoder: expected {frame_size} bytes, got {len(raw_frame)}")
                    break

                frame = np.frombuffer(raw_frame, dtype=np.uint8).reshape((height, width, 3))

                with self.rgb_lock:
                    self.latest_rgb_frame = frame

                frame_count += 1
                if frame_count == 1:
                    print(f"✅ First RGB frame decoded successfully!")

            except Exception as e:
                print(f"❌ Decoder error: {e}")
                break

        print(f"🛑 Decoder thread exiting (decoded {frame_count} frames)")

    def receive_frame(self):
        """Receive one frame packet"""
        try:
            # Read header
            header_data = self._recv_exact(HEADER_SIZE)
            if not header_data:
                return None

            frame_type, timestamp, frame_num, data_size, is_key = struct.unpack(HEADER_FORMAT, header_data)

            # Read payload
            payload = self._recv_exact(data_size)
            if not payload:
                return None

            return {
                'type': frame_type,
                'timestamp': timestamp,
                'frame_num': frame_num,
                'data_size': data_size,
                'is_key': bool(is_key),
                'data': payload
            }

        except Exception as e:
            print(f"❌ Receive error: {e}")
            return None

    def _recv_exact(self, size):
        """Receive exact number of bytes"""
        data = bytearray()
        while len(data) < size:
            chunk = self.client_socket.recv(size - len(data))
            if not chunk:
                return None
            data.extend(chunk)
        return bytes(data)

    def process_frame(self, frame):
        """Process received frame"""
        frame_type = frame['type']

        if frame_type == FRAME_TYPE_METADATA:
            # Parse metadata
            self.metadata = json.loads(frame['data'].decode('utf-8'))
            self.rgb_encoding = str(self.metadata.get('rgbEncoding', 'h264')).lower()
            print(f"\n📋 Session Metadata:")
            print(f"   Session ID: {self.metadata.get('sessionId', 'unknown')}")
            print(f"   RGB: {self.metadata.get('rgbWidth', 1920)}x{self.metadata.get('rgbHeight', 1440)}")
            print(f"   Depth: {self.metadata.get('depthWidth', 256)}x{self.metadata.get('depthHeight', 192)}")
            print(f"   FPS: {self.metadata.get('fps', 'unknown')}")
            print(f"   RGB Encoding: {self.rgb_encoding}")

            rgb_bitrate = self.metadata.get('rgbBitrate')
            if isinstance(rgb_bitrate, (int, float)):
                print(f"   RGB Bitrate: {rgb_bitrate / 1_000_000:.1f} Mbps")
            print()

            if self.rgb_encoding == 'h264':
                if self.h264_pipe is None:
                    if self.start_h264_decoder():
                        print("✅ H.264 decoder started")
                elif self.decoder_thread and not self.decoder_thread.is_alive():
                    self.decoder_thread = threading.Thread(target=self._decode_h264_frames, daemon=True)
                    self.decoder_thread.start()
                    print("✅ H.264 decoder thread restarted")

        elif frame_type == FRAME_TYPE_RGB:
            if self.rgb_encoding in ('jpeg', 'jpg'):
                rgb_array = np.frombuffer(frame['data'], dtype=np.uint8)
                rgb_image = cv2.imdecode(rgb_array, cv2.IMREAD_COLOR)
                if rgb_image is not None:
                    with self.rgb_lock:
                        self.latest_rgb_frame = rgb_image
            else:
                # Send H.264 data to decoder
                if self.h264_pipe:
                    try:
                        self.h264_pipe.stdin.write(frame['data'])
                        self.h264_pipe.stdin.flush()
                    except:
                        pass

            self.frames_received['rgb'] += 1
            self.bytes_received['rgb'] += frame['data_size']

        elif frame_type == FRAME_TYPE_DEPTH:
            # Decode image-compressed depth (PNG/JPEG).
            depth_array = np.frombuffer(frame['data'], dtype=np.uint8)
            depth_image = cv2.imdecode(depth_array, cv2.IMREAD_UNCHANGED)

            if depth_image is not None:
                with self.depth_lock:
                    self.latest_depth_frame = depth_image

            self.frames_received['depth'] += 1
            self.bytes_received['depth'] += frame['data_size']

    def get_latest_frames(self):
        """Get latest RGB and depth frames for display"""
        with self.rgb_lock:
            rgb = self.latest_rgb_frame.copy() if self.latest_rgb_frame is not None else None
        with self.depth_lock:
            depth = self.latest_depth_frame.copy() if self.latest_depth_frame is not None else None
        return rgb, depth

    def get_stats(self):
        """Get streaming statistics"""
        if self.start_time is None:
            return ""

        elapsed = (datetime.now() - self.start_time).total_seconds()
        if elapsed == 0:
            return ""

        rgb_kbps = (self.bytes_received['rgb'] * 8 / 1000) / elapsed
        depth_kbps = (self.bytes_received['depth'] * 8 / 1000) / elapsed
        total_kbps = rgb_kbps + depth_kbps

        rgb_fps = self.frames_received['rgb'] / elapsed
        depth_fps = self.frames_received['depth'] / elapsed

        return (f"RGB: {self.frames_received['rgb']} frames ({rgb_fps:.1f} fps, {rgb_kbps:.0f} kbps) | "
                f"Depth: {self.frames_received['depth']} frames ({depth_fps:.1f} fps, {depth_kbps:.0f} kbps) | "
                f"Total: {total_kbps:.0f} kbps")

    def cleanup(self):
        """Cleanup resources"""
        if self.h264_pipe:
            self.h264_pipe.terminate()
        if self.client_socket:
            self.client_socket.close()
        if self.server_socket:
            self.server_socket.close()

def main():
    print("=" * 60)
    print("  iPhone RGB + Depth Receiver")
    print("=" * 60)
    print()

    # FFmpeg is only required for H.264 streams. JPEG streams work without it.
    try:
        subprocess.run(['ffmpeg', '-version'], capture_output=True, check=True)
    except:
        print("⚠️ FFmpeg not found. H.264 streams will not decode.")
        print("   Install with: brew install ffmpeg (Mac) or sudo apt-get install ffmpeg (Linux)")

    receiver = FrameReceiver(host='0.0.0.0', port=8888)

    try:
        receiver.start()

        # Create display windows
        cv2.namedWindow('RGB Stream', cv2.WINDOW_NORMAL)

        # Resize windows to be more visible
        cv2.resizeWindow('RGB Stream', 960, 720)

        # Move windows to specific positions
        cv2.moveWindow('RGB Stream', 50, 50)

        print("📺 RGB display window opened (should appear on screen)")
        print("   If you don't see it, check Mission Control or other desktops")
        print("Press 'q' to quit\n")

        frame_count = 0
        display_stride = 2
        last_stats_print = datetime.now()

        while True:
            # Receive frame
            frame = receiver.receive_frame()
            if frame is None:
                print("❌ Connection lost")
                break

            # Process frame
            receiver.process_frame(frame)
            frame_count += 1

            # Update display frequently while still keeping CPU headroom.
            if frame_count % display_stride == 0:
                rgb, depth = receiver.get_latest_frames()

                if rgb is not None:
                    cv2.imshow('RGB Stream', rgb)

                # Print stats roughly once per second.
                now = datetime.now()
                if (now - last_stats_print).total_seconds() >= 1.0:
                    print(receiver.get_stats())
                    last_stats_print = now

            # Check for quit
            if cv2.waitKey(1) & 0xFF == ord('q'):
                break

    except KeyboardInterrupt:
        print("\n\n🛑 Interrupted by user")
    except Exception as e:
        print(f"\n❌ Error: {e}")
    finally:
        receiver.cleanup()
        cv2.destroyAllWindows()
        print("👋 Goodbye!")

if __name__ == '__main__':
    main()
