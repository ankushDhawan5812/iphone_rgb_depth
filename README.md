# iPhone RGB + LiDAR Depth Capture & Streaming

Real-time RGB camera and LiDAR depth data capture from iPhone with network streaming and local recording capabilities.

## Overview

This project captures synchronized RGB video and LiDAR depth data from iPhone Pro models (with LiDAR scanner) and provides two modes of operation:

1. **Network Streaming**: Stream RGB (H.264) and depth (PNG) data over TCP to a computer running the Python receiver
2. **Local Recording**: Record RGB and depth video directly to the iPhone's Photos library

The system uses ARKit for camera/LiDAR access, hardware-accelerated H.264 encoding for RGB, and PNG compression for depth maps. The Python receiver decodes streams in real-time using FFmpeg and OpenCV.

## How It Works

### iPhone App (Sender)

1. **ARKit Session**: Captures RGB frames (1920x1440) and depth maps (256x192) from the iPhone's camera and LiDAR scanner
2. **RGB Encoding**: Uses VideoToolbox hardware encoder to compress RGB frames to H.264 format
3. **Depth Compression**: Converts Float32 depth data to 16-bit PNG images for efficient transmission
4. **Network Streaming**: Sends frames over TCP with custom protocol (frame type, timestamp, size headers)
5. **Local Recording**: Optionally records both streams to separate .mov files saved to Photos

### Python Receiver

1. **TCP Server**: Listens on port 8888 for incoming iPhone connection
2. **H.264 Decoding**: Uses FFmpeg subprocess to decode RGB stream in real-time
3. **Depth Decoding**: Uses OpenCV to decode PNG depth frames
4. **Display**: Shows both RGB and depth (colorized) streams in separate windows with statistics

### Protocol

Each frame packet contains:
- Header (18 bytes): frame type (1), timestamp (8), frame number (4), data size (4), keyframe flag (1)
- Payload: H.264 NAL units (RGB) or PNG data (depth)

## Requirements

### iPhone App
- **Device**: iPhone 12 Pro or later (requires LiDAR scanner)
- **iOS**: 14.0 or later
- **Xcode**: 13.0 or later
- **macOS**: Big Sur or later (for development)

### Python Receiver
- **Python**: 3.7+
- **FFmpeg**: Required for H.264 decoding
- **Dependencies**: opencv-python, numpy

## Installation & Setup

### 1. iPhone App Setup

1. **Clone the repository**
   ```bash
   git clone <repo-url>
   cd iphone_rgb_depth
   ```

2. **Open in Xcode**
   ```bash
   open iphone_rbg_depth.xcodeproj
   ```

3. **Configure signing**
   - Select the project in Xcode
   - Go to "Signing & Capabilities"
   - Select your development team
   - Xcode will automatically create a provisioning profile

4. **Connect iPhone**
   - Connect your iPhone 12 Pro or later via USB
   - Trust the computer if prompted
   - Select your device as the build target

5. **Build and run**
   - Press Cmd+R or click the Run button
   - Grant camera permission when prompted

### 2. Python Receiver Setup

1. **Install FFmpeg**
   ```bash
   # macOS
   brew install ffmpeg

   # Linux
   sudo apt-get install ffmpeg
   ```

2. **Create virtual environment (recommended)**
   ```bash
   python3 -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```

3. **Install dependencies**
   ```bash
   pip install opencv-python numpy
   ```

## Usage

### Streaming Mode

1. **Start the receiver on your computer**
   ```bash
   python3 receiver.py
   ```

   You should see:
   ```
   🎧 Server listening on 0.0.0.0:8888
   📱 Waiting for iPhone connection...
   ```

2. **Configure iPhone app**
   - Make sure iPhone and computer are on the same WiFi network
   - In the app, enter your computer's IP address (e.g., 192.168.1.100)
   - Port should be 8888

3. **Start streaming**
   - Tap "Start Streaming" button in the iPhone app
   - Receiver will display RGB and depth streams
   - Press 'q' in the receiver window to quit

### Recording Mode

1. **Grant Photos permission**
   - When first recording, the app will request Photos access
   - Grant permission in Settings if needed

2. **Start/Stop recording**
   - Tap "Start Recording" button
   - Record your scene (RGB and depth are captured simultaneously)
   - Tap "Stop Recording"
   - Videos are automatically saved to Photos library as separate files

## Project Structure

```
iphone_rgb_depth/
├── iphone_rbg_depth/               # iOS app source
│   ├── ARViewController.swift      # Main ARKit controller
│   ├── ARViewControllerRepresentable.swift  # SwiftUI wrapper
│   ├── ContentView.swift           # App UI
│   ├── VideoRecorder.swift         # Local recording functionality
│   ├── DepthImageConverter.swift   # Depth processing utilities
│   ├── DepthCompressor.swift       # Depth PNG compression
│   └── iphone_rbg_depthApp.swift  # App entry point
├── receiver.py                     # Python receiver script
├── iphone_rbg_depth.xcodeproj/    # Xcode project
└── README.md                       # This file
```

## Current Status

### ✅ Completed Features

- ✅ ARKit session with LiDAR support
- ✅ RGB frame capture (1920x1440)
- ✅ Depth frame capture (256x192)
- ✅ Hardware H.264 encoding (VideoToolbox)
- ✅ PNG depth compression
- ✅ Network streaming (TCP protocol)
- ✅ Python receiver with FFmpeg decoding
- ✅ Real-time display (RGB + depth visualization)
- ✅ Local recording to .mov files
- ✅ Photos library integration
- ✅ FPS monitoring and statistics
- ✅ LiDAR availability detection

### 🚧 Known Limitations

- Network streaming requires manual IP configuration
- No automatic reconnection on network failure
- Depth range fixed to 0.5-5.0 meters
- Recording orientation locked to portrait

## Technical Details

### Video Specifications

| Stream | Resolution | Format | Bitrate | FPS |
|--------|-----------|--------|---------|-----|
| RGB | 1920x1440 | H.264 | 2 Mbps | 30 |
| Depth | 256x192 | PNG (16-bit) | ~100-200 KB/frame | 30 |

### Performance

- **Latency**: Typically 50-150ms end-to-end (network dependent)
- **CPU Usage**: ~30-40% on iPhone (hardware encoding)
- **Network Bandwidth**: ~2-3 Mbps total

## Troubleshooting

### iPhone App Issues

**App crashes on launch**
- Ensure device has LiDAR (iPhone 12 Pro or later)
- Check camera permissions in Settings

**"LiDAR Not Supported" message**
- Verify device model (must be iPhone 12 Pro, 13 Pro, 14 Pro, 15 Pro)
- Restart the app

### Receiver Issues

**"FFmpeg not found" error**
- Install FFmpeg: `brew install ffmpeg` (Mac) or `sudo apt-get install ffmpeg` (Linux)
- Verify: `ffmpeg -version`

**Connection timeout**
- Ensure iPhone and computer on same WiFi
- Check firewall settings (allow port 8888)
- Verify IP address is correct

**No video display**
- Check that OpenCV windows appear (may be in another desktop/space)
- Press 'q' to quit if windows are frozen

## Development Notes

- Built with Swift 5.0+ and SwiftUI
- Uses ARKit, AVFoundation, VideoToolbox, Network frameworks
- Requires physical device (LiDAR not available in simulator)
- Python receiver uses subprocess for FFmpeg integration

## License

Educational/Personal Project
